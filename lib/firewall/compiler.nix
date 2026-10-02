{
  lib,
  mkMacAddress,
  mkContainerVethName,
}:
{
  hostName,
  services,
  inventory,
  ipv4,
}:
with lib;
let
  addr = import ./address.nix { inherit lib; };
  inherit (addr) fail;
  q = builtins.toJSON;
  lines = concatStringsSep "\n";
  nftSet = values: "{ ${concatStringsSep ", " values} }";
  safe = value: builtins.isString value && builtins.match "[a-zA-Z0-9_.:/-]+" value != null;
  networks = inventory.networks or { };
  defaults = {
    mode = "off";
    ingress = { };
    egress = [ ];
    infrastructure = [ ];
  };
  standardGroups = {
    rfc1918 = [
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
    ];
    ula = [ "fc00::/7" ];
    cgnat = [ "100.64.0.0/10" ];
    link-local = [
      "169.254.0.0/16"
      "fe80::/10"
    ];
    multicast = [
      "224.0.0.0/4"
      "ff00::/8"
    ];
    homelab = concatMap (
      n: optional (n.ipv6Prefix or null != null) n.ipv6Prefix ++ optional (n.ipv4Prefix or null != null) n.ipv4Prefix
    ) (attrValues networks);
  };
  groups = standardGroups // (inventory.groups or { });
  serviceFor =
    name:
    let
      matches = filter (s: s.name == name || s.key == name) (attrValues normalized);
    in
    if length matches != 1 then fail "service '${name}' is missing or ambiguous" else head matches;
  normalized = mapAttrs (
    key: service:
    service
    // {
      inherit key;
      policy = defaults // (service.networkPolicy or { });
      attachments =
        service.attachments or (listToAttrs (
          map (
            vlan:
            nameValuePair (toString vlan) {
              interface = mkContainerVethName service.name vlan;
              mac = mkMacAddress "${service.name}:${toString vlan}";
              network = toString vlan;
            }
          ) (service.vlans or [ ])
        ));
    }
  ) services;
  local = filterAttrs (_: s: s.host == hostName && s.policy.mode != "off") normalized;
  attachmentFor =
    service: selected:
    if selected == null then
      if length (attrNames service.attachments) == 1 then
        head (attrNames service.attachments)
      else
        fail "${service.key}: select an attachment explicitly"
    else if hasAttr selected service.attachments then
      selected
    else
      fail "${service.key}: unknown attachment '${selected}'";
  identity =
    service: attachment:
    let
      a = service.attachments.${attachment};
      network = networks.${a.network} or (fail "${service.key}/${attachment}: missing network '${a.network}'");
      mac = toLower a.mac;
      v4 = (ipv4.${service.key} or ipv4.${service.name} or { }).${attachment} or null;
      prefix = network.ipv6Prefix or null;
      v6 = optional (prefix != null) (addr.fromMac prefix mac);
      ll = addr.linkLocal mac;
      valid4 = v4 == null || (network.ipv4Prefix or null != null && addr.contains4 network.ipv4Prefix v4);
    in
    if service ? vlans && prefix == null then
      fail "${service.key}/${attachment}: VLAN requires one ipv6Prefix"
    else if !valid4 then
      fail "${service.key}/${attachment}: IPv4 address outside its declared subnet"
    else if v4 == null && !(a.ipv6Only or false) then
      fail "${service.key}/${attachment}: missing IPv4 inventory (or explicit ipv6Only)"
    else if !safe a.interface || stringLength a.interface > 15 then
      fail "invalid host interface name"
    else
      builtins.deepSeq (addr.eui64 mac) {
        inherit
          mac
          network
          v4
          v6
          ll
          attachment
          ;
        inherit (a) interface;
        networkName = a.network;
        service = service.key;
        addresses = optional (v4 != null) v4 ++ v6;
      };
  resolve =
    selector:
    let
      choices = filter (x: x) [
        (selector.service or null != null)
        (selector.host or null != null)
        (selector.group or null != null)
        (selector.cidrs or [ ] != [ ])
      ];
      result =
        if selector.service or null != null then
          let
            s = serviceFor selector.service;
            a = attachmentFor s (selector.attachment or null);
          in
          map addr.host (identity s a).addresses
        else if selector.host or null != null then
          map addr.host (inventory.hosts.${selector.host} or (fail "unknown host '${selector.host}'"))
        else if selector.group or null != null then
          groups.${selector.group} or (fail "unknown group '${selector.group}'")
        else
          selector.cidrs or [ ];
    in
    if length choices != 1 then
      fail "a peer must select exactly one service, host, group or CIDR list"
    else
      map addr.cidr result;
  endpoint =
    s: name:
    let
      ep = s.endpoints.${name} or (fail "${s.key}: missing endpoint '${name}'");
    in
    if !(ep.expose or true) then fail "${s.key}: endpoint '${name}' is not exposed" else ep;
  transports =
    ep:
    if ep.transport == "tcp-and-udp" then
      [
        "tcp"
        "udp"
      ]
    else
      [ ep.transport ];
  baseRule = rule: {
    via = rule.via or null;
    peer = rule.to;
    protocol = rule.protocol or "tcp";
    ports = rule.ports or [ ];
    allPorts = rule.allPorts or false;
    icmpTypes = rule.icmpTypes or [ ];
  };
  outRules =
    origin: rules:
    concatMap (
      r:
      if r.endpoint or null != null then
        let
          ep = endpoint (serviceFor (r.to.service or (fail "endpoint requires a service selector"))) r.endpoint;
        in
        map (
          protocol:
          baseRule r
          // {
            inherit protocol origin;
            ports = [ ep.port ];
            allPorts = false;
          }
        ) (transports ep)
      else
        [ (baseRule r // { inherit origin; }) ]
    ) rules;
  inRules =
    s: origin: grants:
    concatLists (
      mapAttrsToList (
        name: grant:
        let
          ep = endpoint s name;
        in
        concatMap (
          peer:
          map (protocol: {
            inherit peer protocol origin;
            via = grant.via or null;
            ports = [ ep.port ];
            allPorts = false;
            icmpTypes = [ ];
          }) (transports ep)
        ) grant.from
      ) grants
    );
  dependency =
    s: name:
    if name == "database" then
      if s.database or null == null then
        fail "${s.key}: database profile without database metadata"
      else
        {
          egress = [
            {
              to.service = s.database.instance;
              endpoint = "postgres";
            }
          ];
          ingress = { };
        }
    else
      inventory.infrastructure.${name} or (fail "unknown infrastructure profile '${name}'");
  rulesFor =
    s:
    let
      deps = map (name: {
        inherit name;
        value = dependency s name;
      }) s.policy.infrastructure;
    in
    {
      egress =
        outRules "explicit" s.policy.egress ++ concatMap (d: outRules "infrastructure:${d.name}" (d.value.egress or [ ])) deps;
      ingress =
        inRules s "explicit" s.policy.ingress
        ++ concatMap (d: inRules s "infrastructure:${d.name}" (d.value.ingress or { })) deps;
    };
  expanded =
    s: direction: attachment:
    filter (r: r.attachment == attachment) (
      map (
        r:
        let
          a = attachmentFor s r.via;
          valid =
            if
              elem r.protocol [
                "tcp"
                "udp"
              ]
            then
              (r.ports != [ ] || r.allPorts) && r.icmpTypes == [ ]
            else
              elem r.protocol [
                "icmp"
                "icmpv6"
              ]
              && r.ports == [ ]
              && !r.allPorts
              && r.icmpTypes != [ ]
              && all (t: elem t (if r.protocol == "icmp" then [ 8 ] else [ 128 ])) r.icmpTypes;
        in
        if !valid then
          fail "${s.key}: specify TCP/UDP ports (or allPorts), or ICMP echo-request type"
        else
          r
          // {
            attachment = a;
            cidrs = resolve r.peer;
          }
      ) (rulesFor s).${direction}
    );
  localPorts = unique (
    concatMap (s: map (a: a.interface) (attrValues s.attachments)) (
      attrValues (filterAttrs (_: s: s.host == hostName) normalized)
    )
  );
  allIdentities = concatMap (s: map (a: identity s a) (attrNames s.attachments)) (attrValues local);
  # Validate known peers too, without requiring unrelated off-mode inventory.
  knownIdentities = concatMap (
    s:
    map (a: identity s a) (
      filter (a: hasAttr a (ipv4.${s.key} or ipv4.${s.name} or { }) || hasAttr s.key local) (attrNames s.attachments)
    )
  ) (attrValues normalized);
  duplicate = xs: length xs != length (unique xs);
  collision =
    duplicate (map (i: "${i.networkName}/${i.mac}") knownIdentities)
    || duplicate (concatMap (i: map (ip: "${i.networkName}/${addr.host ip}") i.addresses) knownIdentities)
    || duplicate (map (i: i.interface) allIdentities);
  deny = mode: label: ''
    limit rate 3/second burst 5 packets log prefix ${q "hlfw ${builtins.substring 0 30 label} "}
    counter ${if mode == "audit" then "return" else "drop"}
  '';
  # Re-evaluate both original traffic and replies against current grants. Never
  # cache a policy allow in a guest-controllable packet mark or global CT bypass.
  grant =
    direction: reply: r:
    let
      incoming = direction == "ingress";
      peerField = if incoming != reply then "saddr" else "daddr";
      portField = if reply then "sport" else "dport";
      isIcmp = elem r.protocol [
        "icmp"
        "icmpv6"
      ];
      family = cidr: if hasInfix ":" cidr then "ip6" else "ip";
      matching = filter (cidr: !isIcmp || (r.protocol == "icmpv6") == (family cidr == "ip6")) r.cidrs;
      state = if reply then "ct direction reply ct state established" else "ct direction original";
      protocol = if r.protocol == "icmpv6" then "ipv6-icmp" else r.protocol;
      port =
        if isIcmp then
          "${r.protocol} type ${nftSet (map (t: toString (if reply then (if t == 8 then 0 else 129) else t)) r.icmpTypes)}"
        else
          optionalString (!r.allPorts) "${r.protocol} ${portField} ${nftSet (map toString r.ports)}";
    in
    lines (
      map (cidr: "${state} ${family cidr} ${peerField} ${cidr} meta l4proto ${protocol} ${port} counter return") matching
    );
  attachmentRules =
    s: a:
    let
      i = identity s a;
      suffix = builtins.substring 0 12 (builtins.hashString "sha256" "${s.key}/${a}");
      chain = dir: "${dir}_${suffix}";
      v6set = nftSet (i.v6 ++ [ i.ll ]);
      otherPorts = filter (port: port != i.interface) localPorts;
      ndTargets = nftSet (
        map (ip: "0x${concatMapStrings (n: fixedWidthString 4 "0" (toLower (toHexString n))) (addr.ipv6 ip)}") (
          i.v6 ++ [ i.ll ]
        )
      );
      rawMac = "0x${replaceStrings [ ":" ] [ "" ] i.mac}";
      ndOption = type: "@th,192,16 ${if type == "ns" then "0x0101" else "0x0201"} @th,208,48 ${rawMac}";
      out = expanded s "egress" a;
      incoming = expanded s "ingress" a;
      dhcp = map (server: builtins.deepSeq [ (addr.eui64 server.mac) (addr.ipv4 server.ipv4) ] server) (
        i.network.dhcpServers or [ ]
      );
      routers = map (router: builtins.deepSeq [ (addr.eui64 router.mac) (addr.ipv6 router.ipv6) ] router) (
        i.network.routers or [ ]
      );
      v4self = optionalString (i.v4 != null) "ip saddr ${i.v4} return";
      ctrlOut = ''
        arp operation { request, reply } return
        ${optionalString (i.v4 != null) ''
          ip saddr { 0.0.0.0, ${i.v4} } ip daddr 255.255.255.255 udp sport 68 udp dport 67 return
          ${lines (map (server: "ip saddr ${i.v4} ip daddr ${server.ipv4} udp sport 68 udp dport 67 return") dhcp)}
        ''}
        # No fragmented/extension-header ND. Other fragments use conntrack.
        ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type 133 ip6 saddr ${i.ll} ip6 daddr ff02::2 ip6 length 8 return
        ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type 133 ip6 saddr ${i.ll} ip6 daddr ff02::2 ip6 length 16 @th,64,16 0x0101 @th,80,48 ${rawMac} return
        ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type 135 ip6 saddr :: @th,64,128 ${ndTargets} ip6 length 24 return
        ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type 135 ip6 saddr ${v6set} ip6 length 24 return
        ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type 135 ip6 saddr ${v6set} ip6 length 32 ${ndOption "ns"} return
        ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type 136 @th,64,128 ${ndTargets} ip6 length 24 return
        ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type 136 @th,64,128 ${ndTargets} ip6 length 32 ${ndOption "na"} return
        # Only link-local MLD reports/done (not router queries).
        ip6 saddr ${i.ll} ip6 daddr ff02::/16 ip6 hoplimit 1 meta l4proto ipv6-icmp icmpv6 type { 131, 132, 143 } return
      '';
      ctrlIn = ''
        # Router/DHCP identities cannot originate from ordinary local service ports,
        # including ports whose application policy is still off.
        iifname ${nftSet (map q localPorts)} meta l4proto ipv6-icmp icmpv6 type 134 jump ${chain "deny"}
        iifname ${nftSet (map q localPorts)} udp sport 67 udp dport 68 jump ${chain "deny"}
        ${optionalString (i.v4 != null) ''
          ether type arp arp daddr ip ${i.v4} return
          ${lines (map (server: "ether saddr ${server.mac} ip saddr ${server.ipv4} udp sport 67 udp dport 68 return") dhcp)}
        ''}
        ${lines (
          map (
            router:
            "ether saddr ${router.mac} ip6 saddr ${router.ipv6} ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type 134 return"
          ) routers
        )}
        ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 code 0 icmpv6 type { 135, 136 } return
        ip6 saddr fe80::/10 ip6 daddr ff02::/16 ip6 hoplimit 1 meta l4proto ipv6-icmp icmpv6 type 130 return
      '';
      errors = ''
        ct state related meta l4proto icmp icmp type { 3, 11, 12 } return
        ct state related meta l4proto ipv6-icmp icmpv6 type { 1, 2, 3, 4 } return
      '';
      controlDeny = ''
        meta l4proto ipv6-icmp icmpv6 type { 133, 134, 135, 136, 137 } jump ${chain "deny"}
        udp sport { 67, 68 } udp dport { 67, 68 } jump ${chain "deny"}
      '';
    in
    {
      identity = i;
      report = {
        inherit (s.policy) mode;
        identity = i;
        egress = out;
        ingress = incoming;
      };
      ingressDispatch = "oifname ${q i.interface} jump ${chain "in"}";
      egressDispatch = "iifname ${q i.interface} jump ${chain "out"}";
      guardDispatch = "iifname ${q i.interface} jump ${chain "guard"}";
      ownershipDispatch = optionalString (otherPorts != [ ]) ''
        iifname ${nftSet (map q otherPorts)} ether saddr ${i.mac} jump ${chain "deny"}
        ${optionalString (i.v4 != null) "iifname ${nftSet (map q otherPorts)} ip saddr ${i.v4} jump ${chain "deny"}"}
        ${optionalString (i.v4 != null) "iifname ${nftSet (map q otherPorts)} arp saddr ip ${i.v4} jump ${chain "deny"}"}
        iifname ${nftSet (map q otherPorts)} ip6 saddr ${v6set} jump ${chain "deny"}
        iifname ${nftSet (map q otherPorts)} meta l4proto ipv6-icmp icmpv6 type 136 @th,64,128 ${ndTargets} jump ${chain "deny"}
      '';
      text = ''
        chain ${chain "deny"} { ${deny s.policy.mode "${s.name}/${a}"} }
        chain ${chain "guard"} {
          ether saddr != ${i.mac} jump ${chain "deny"}
          ether type { 0x8100, 0x88a8 } jump ${chain "deny"}
          ether type ip6 exthdr frag exists jump ${chain "deny"}
          ${optionalString (i.v4 != null) ''
            ether type arp arp saddr ether ${i.mac} arp saddr ip ${i.v4} arp operation { request, reply } return
            ether type arp arp saddr ether ${i.mac} arp saddr ip 0.0.0.0 arp daddr ip ${i.v4} arp operation request return
          ''}
          ${v4self}
          ${optionalString (i.v4 != null) "ip saddr 0.0.0.0 udp sport 68 udp dport 67 return"}
          ip6 saddr ${v6set} return
          ip6 saddr :: ip6 nexthdr ipv6-icmp ip6 hoplimit 255 icmpv6 type 135 @th,64,128 ${ndTargets} ip6 length 24 return
          jump ${chain "deny"}
        }
        chain ${chain "out"} {
          ${ctrlOut}
          ct state invalid jump ${chain "deny"}
          ${controlDeny}
          ${errors}
          ${lines (map (grant "egress" false) out)}
          ${lines (map (grant "ingress" true) incoming)}
          jump ${chain "deny"}
        }
        chain ${chain "in"} {
          ${ctrlIn}
          ct state invalid jump ${chain "deny"}
          ${controlDeny}
          ${errors}
          ${optionalString (i.v4 != null) "ether type ip ip daddr != ${i.v4} jump ${chain "deny"}"}
          ${optionalString (i.v4 == null) "ether type ip jump ${chain "deny"}"}
          ether type ip6 ip6 daddr != ${v6set} jump ${chain "deny"}
          ${lines (map (grant "ingress" false) incoming)}
          ${lines (map (grant "egress" true) out)}
          jump ${chain "deny"}
        }
      '';
    };
  compiled = concatMap (s: map (attachmentRules s) (attrNames s.attachments)) (attrValues local);
  dispatch = name: lines (map (a: a.${name}) compiled);
  contents = ''
    ${lines (map (a: a.text) compiled)}
    chain identity_guard {
      type filter hook prerouting priority -300; policy accept;
      ${dispatch "ownershipDispatch"}
      ${dispatch "guardDispatch"}
    }
    # After bridge conntrack, before VLAN tags are materialized for host input.
    # This checks source egress once, for both routed/local and bridged packets.
    chain from_container {
      type filter hook prerouting priority -150; policy accept;
      ${dispatch "ownershipDispatch"}
      ${dispatch "egressDispatch"}
    }
    chain between_ports {
      type filter hook forward priority 0; policy accept;
      ${dispatch "ingressDispatch"}
    }
    chain to_container {
      type filter hook output priority 0; policy accept;
      ${dispatch "ingressDispatch"}
    }
  '';
in
if any (s: s.attachments == { }) (attrValues local) then
  fail "an active service policy needs at least one attachment"
else if collision then
  fail "duplicate service MAC, IP address or host interface"
else
  builtins.deepSeq compiled {
    inherit contents;
    report = map (a: a.report) compiled;
    containerNames = map (s: s.name) (attrValues local);
    interfaces = map (a: a.identity.interface) compiled;
  }
