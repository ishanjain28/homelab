# Host-enforced service network policy

Status: original design, retained for rationale. An opt-in implementation now
exists; see [network/README.md](network/README.md) for the actual API, rollout
instructions and current limitations. The examples below describe the proposal
and are not the final option syntax. No production policies have been enabled.
This supplements `firewall-design.md` without changing its original text.

## Recommendation

Compile declarative service policies into host-owned nftables bridge rules.
Identify a container by its host-side veth, validate its MAC and source addresses,
then enforce default-deny ingress and egress. Resolve service references into
exact addresses using a shared network inventory and the existing deterministic
MAC generation. Do not rely on a firewall inside the container or on the router
seeing traffic between containers on the same VLAN.

This protects against a compromised application, including one that can change
network settings inside its container. Host root and kernel escapes remain
outside this boundary. Policy applies to the whole container, including helpers,
not separately to each process inside it.

## 1. Explicit network inventory

Keep an ordinary Nix inventory shared by host configurations and the policy
compiler. A network domain identifies one connected network; VLAN numbers alone
are not globally unique across sites.

```nix
networkInventory.domains.home.vlans = {
  "50" = {
    ipv6Prefix = "2a0a:6040:4004:50::/64";
    ipv4Prefixes = [ "10.0.50.0/24" ];
  };
  "99" = {
    # Documentation example: this can be any assigned /64, independently of ID.
    ipv6Prefix = "2001:db8:abcd:1234::/64";
    ipv4Prefixes = [ "10.0.99.0/24" ];
  };
};
```

Each VLAN has exactly one IPv6 prefix, represented by a single `ipv6Prefix`
string. Require /64 for this EUI-64 SLAAC design. Each service attachment derives
one global/ULA address from that prefix, in addition to its link-local address.
Do not derive the prefix from the VLAN number: IPv6 hextets are
hexadecimal, so the written hextet `50` is not decimal 50.

Also declare routers (MAC and link-local address), authorized DHCP servers,
resolvers, infrastructure hosts, and IPv4 reservations. These are explicit
inventory entries, not values inferred from arbitrary router advertisements or
DNS responses. Prefix membership does not itself authorize traffic.

For Manaslu, represent the untagged container bridge as a named network with
prefixes and attachments. Do not invent VLAN 0 or require tagging on that host.
The same policy compiler can use its bridge/veth identities.

## 2. Derive service addresses from existing identity

`lib/services/default.nix` already generates a stable host-side veth for each
service/VLAN pair and assigns a MAC using `mkMacAddress "${name}:${vlan}"`.
The guest uses `Token = "eui64"` and disables IPv6 privacy addresses.

For each attachment, the compiler should:

1. Obtain the MAC from the existing helper; do not introduce a second algorithm.
2. Flip the first octet's universal/local bit and insert `ff:fe` in the middle.
3. Combine that 64-bit interface identifier with the VLAN's configured /64 prefix.
4. Derive its link-local address separately and scope it to this attachment.
5. Export the resulting exact addresses, MAC and host veth in the service registry.

For example, Seerr on VLAN 50 currently derives:

```text
MAC:       02:97:bc:80:c9:02
IID:       0097:bcff:fe80:c902
Prefix:    2a0a:6040:4004:50::/64
Address:   2a0a:6040:4004:50:97:bcff:fe80:c902
Link-local fe80::97:bcff:fe80:c902
```

Rules authorizing Seerr use its /128 addresses, not the entire VLAN /64. Parse
and normalize IPv6 addresses properly; string concatenation cannot handle every
valid compressed prefix. The EUI-64 transformation is specified in
[RFC 4291, Appendix A](https://www.rfc-editor.org/rfc/rfc4291.html).

Preserve the existing MAC seed: changing it would also change DHCP identity and
IPv6 addresses. Reject duplicate MACs or addresses within a connected network
across the fleet. Host-qualified service names alone do not prevent collisions:
the current MAC seed does not include the host name.

### IPv4 cannot be left unrestricted

EUI-64 solves IPv6 identity only. Require declared static IPv4 addresses or DHCP
reservations for IPv4-enabled attachments in the first implementation. Use these
exact addresses in source validation and service selectors. A trusted DHCP lease
integration could come later; learning identity from guest packets is unsafe.

If an attachment has no authoritative IPv4 identity, either reject enforcement
configuration or explicitly make it IPv6-only and block IPv4 on its host veth.
Allowing a whole IPv4 subnet as its source would enable impersonation.

## 3. Policy API

Keep the existing endpoints as the source of listening ports and transports.
An endpoint declaration must no longer imply unrestricted incoming access.

Illustrative syntax, with endpoint and service names resolved against the actual
registry during implementation:

```nix
homelab.services.seerr.networkPolicy = {
  mode = "enforce"; # also "audit" during rollout

  ingress.web = {
    viaVlan = 50;
    from = [
      { service = "annapurna/caddy"; vlan = 50; }
      { group = "admin-devices"; }
    ];
  };

  egress.allow = [
    {
      viaVlan = 50;
      to = { service = "annapurna/postgresql-home-primary"; vlan = 50; };
      endpoint = "postgres";
    }
    {
      viaVlan = 50;
      to.host = "radarr-normal";
      protocol = "tcp";
      ports = [ 7878 ];
    }
    {
      viaVlan = 50;
      to.host = "sonarr-normal";
      protocol = "tcp";
      ports = [ 8989 ];
    }
  ];

  infrastructure = {
    dns = "internal";
    logging = true;
    monitoring = true;
  };
};
```

The example demonstrates local dependencies, not a complete Seerr policy.
Metadata providers, notifications and other enabled integrations need additional
permissions. Normal and 4K instances are separate named destinations.

Semantics:

- Unlisted new ingress and egress are denied in enforce mode.
- Replies to authorized connections are allowed; a reply is not a general grant
  to initiate new connections in the opposite direction.
- A service destination plus endpoint resolves to its exact addresses, transport
  and destination ports. Reject missing services/endpoints and endpoints that are
  not exposed, rather than silently widening access.
- Omit `viaVlan` only when there is one unambiguous source attachment. A
  multihomed destination also needs an explicit attachment selector. Never union
  every address of a multihomed service into every rule.
- Explicit TCP/UDP rules specify destination ports or an explicit all-ports
  choice. ICMP rules specify types/codes, not ports. Other IP protocols require
  an explicit protocol grant.
- An outgoing grant does not automatically authorize the server's incoming side.
  Both must allow a new connection. An optional server setting to accept declared
  consumers can generate narrow incoming grants, but must be explicit and visible
  in the effective policy.
- Infrastructure adapters generate concrete permissions for DNS, database,
  logging and monitoring from declared metadata. They are not an implicit
  unrestricted infrastructure network exception. Disabled features generate none.

Maintain named address sets such as `rfc1918`, `ula`, `cgnat`, `link-local`,
`multicast`, `homelab`, and `admin-devices`. A group is a reusable selector,
not a trust level or an automatic allow. `homelab` must include your public IPv6
prefixes and other owned routed ranges. `internet` needs explicit exclusion of
local, owned and special-purpose ranges in both families; it is not merely
the complement of RFC 1918.

## 4. Host enforcement architecture

Use one managed nftables bridge table per host, with dispatch by exact host-side
interface names and per-attachment chains/sets. nftables bridge filtering supports
stateful filtering and sees traffic that stays on a bridge.
[Bridge filtering reference](https://wiki.nftables.org/wiki-nftables/index.php/Bridge_filtering)

| Path | Required checks |
| --- | --- |
| Container to uplink | Source identity and source egress |
| Uplink to container | Destination ingress |
| Container A to B | A identity and egress, then B ingress |
| Container to host | Container egress plus the host's input policy |
| Host to container | Container ingress plus the host's output policy |

Cover bridge input, forward and output. Add early bridge prerouting guards for
source MAC validation before bridge source learning. On routed paths, enforce
at the container attachment as packets enter or leave it, including paths through
host routing/NAT. Verify those paths in tests rather than assuming bridge forward
sees every packet.

A successful source check must return to the dispatcher so the destination check
still runs. An early `accept` in A's egress chain must not bypass B's ingress.
Source validation runs before established-flow shortcuts. Connection tracking
must authorize replies without admitting a connection that never passed both
applicable initial policy checks; test retransmissions and asymmetric paths.

Do not globally enable bridge-to-iptables compatibility as the policy mechanism.
Load the bridge conntrack support required by the deployed kernel. Do not apply
flow offload to managed traffic if it bypasses policy evaluation. Choose hook
priorities deliberately alongside existing nftables tables.
[nftables reference](https://netfilter.org/projects/nftables/manpage.html)

Unrelated host management and VM traffic remains governed by its existing
firewall. Only managed attachments enter these service chains. Native host
services such as BIRD and host WireGuard need their own host input/output policy;
they are not isolated by container veth rules.

Audit the complete set of container interfaces. In the pinned NixOS container
module, `privateNetwork` alone does not add the default `ve-*` pair: address/MAC
options or a host bridge can introduce it. Assert that no ungoverned default veth,
passed-through physical NIC or extra network attachment is introduced later.
An unaddressed interface is not a security boundary: a compromised guest can
assign an address. Remove unused attachments or explicitly quarantine them.

## 5. Source validation and necessary control traffic

Dropping unlisted TCP/UDP connections is insufficient on a shared L2 network.
Each managed attachment needs these guards:

- Ethernet source must equal the assigned MAC.
- IPv4 and IPv6 sources must belong to that attachment's exact address sets,
  with narrow exceptions for DHCP and IPv6 duplicate-address detection.
- ARP sender MAC/address must match its inventory identity; permit only the
  required address-probe exception using source 0.0.0.0.
- Allow DHCP client traffic only as needed, and responses only from declared
  server paths/identities. Deny container DHCP server messages unless explicitly
  configured as that infrastructure role.
- Permit router advertisements only from declared router identities on trusted
  paths. Deny advertisements and redirects originating from ordinary services.
- Validate neighbour-discovery hop limits, source identities and link-layer
  options. Neighbour advertisements may claim only that attachment's own target
  addresses. A valid source IP alone does not prevent claiming someone else's
  address in the NA target field.
- Allow unspecified-source neighbour solicitation only for duplicate-address
  detection of the attachment's own addresses. Reject fragmented ND as specified
  in [RFC 6980](https://www.rfc-editor.org/rfc/rfc6980.html).
- Preserve necessary ICMPv6 errors, especially Packet Too Big, and the required
  ND/MLD control traffic. Echo access is a separate permission. Do not permit all
  multicast applications just because control-plane multicast is necessary.
  [ICMPv6 filtering guidance](https://www.rfc-editor.org/info/rfc4890/)
- Keep VLAN access-port filtering and reject guest attempts to inject tags or
  change VLAN membership. Test tagged, double-tagged and priority-tagged frames:
  bridge PVID metadata means a naive EtherType-only rule is not enough.

Use IPv6 extension-header-aware transport matching and test fragmented traffic
with bridge conntrack/reassembly. Unknown L2/IP protocols remain denied unless
explicitly supported. Do not trust packet marks supplied by the guest.

Host-side enforcement of these checks is mandatory. Guest networkd settings are
useful defaults but are not a security boundary.

## 6. Important limitations

**Encrypted tunnels:** qBittorrent currently runs its VPN inside the container.
The host sees the VPN endpoint and encrypted packets, not the inner destination
or port. It can restrict VPN endpoints and bootstrap access, but cannot truthfully
enforce destination restrictions inside that tunnel. Either declare this a VPN
egress exception, or move the tunnel to a host-owned gateway/network namespace
where inner traffic can be filtered. Treat access to other proxies/relays with
the same care.

**Domains and HTTPS:** DNS-resolved allowlists are unreliable for shared/CDN
addresses and changing records. Use a controlled egress proxy for domain-based
HTTP(S) restrictions where feasible. Allowing arbitrary TCP 443 is broad Internet
access and permits many tunnels. Nix evaluation should not resolve live DNS to
decide security policy.

**Reverse proxies:** Seerr sees Caddy as the network peer. Restricting who may
use a Caddy route requires a corresponding policy at Caddy; service ingress
rules cannot recover the original client identity from a TCP connection.

**Shared L2:** veth identity strongly identifies local containers. An external
host's IP/MAC is only as trustworthy as the network carrying it. For mutually
hostile devices, use switch protections, segmentation or authenticated tunnels;
address allowlists do not provide cryptographic peer identity.

## 7. Atomic lifecycle and revocation

Integrate through NixOS `networking.nftables.tables`, preserving other owned
tables. Install replacements in one nft transaction; never flush the active
policy and add rules in a later command. An invalid replacement must leave the
old policy active.

Container networking must not become usable before its rules exist. Coordinate
container unit startup with the firewall and test startup failures. The pinned
nftables unit deletes owned tables on stop, so startup `After`/`Requires` alone
is insufficient: container shutdown/quarantine must precede removal, or the
policy lifecycle must retain its deny boundary through restarts. Test reload,
restart, stop and failed activation explicitly before enabling enforcement.

Policy tightening must revoke existing sessions too. Plan targeted conntrack
deletion for affected service addresses in both families, with attachments
temporarily quarantined while rules/state change if needed to avoid races.
Do not flush all host conntrack state or disrupt unrelated management sessions.
Entering enforce mode from audit must also discard flows that were never
authorized under the new policy.

For IPv6 renumbering, replace the single prefix in inventory and coordinate the
firewall rollout with the router advertisement change. Remove old derived
addresses from policy and clear their connection state. Stale guest addresses
remain blocked even if their SLAAC lifetime has not expired. This design does
not promise a seamless transition: connectivity may be interrupted until rules
and addresses agree. Unknown prefixes must not silently widen access. No live
RA-driven expansion of allowlists.

## 8. Repository implementation plan

1. Add shared network inventory and address helpers under `lib/networking`.
   Unit-test EUI-64, compressed IPv6 parsing, prefix validation and collisions.
2. Extend service options and the base registry with attachment identities and
   uncompiled policies. Preserve endpoint ports and existing MAC generation.
3. Add `lib/firewall` to resolve groups/service endpoints, validate dependencies,
   and generate nftables sets/chains plus a readable effective-policy report.
4. Add a host platform module that installs rules and handles lifecycle/state
   revocation. Keep the host management firewall separate.
5. Add explicit dependency adapters for logging, metrics and databases. Show
   each generated grant and its origin in the report.
6. Roll out audit mode on a small service, review counters and rate-limited deny
   logs, then enforce it. Do not automatically convert observed traffic to grants.
   Move to Seerr and other complex services after the simple case is proven.

The fleet registry must remain an acyclic input: identities and declarations
first, then policy compilation. Do not build registry entries from compiled
rules that themselves depend on the fleet registry. Reject missing selectors,
ambiguous attachments, duplicate identities and unsupported overlapping routing
domains at evaluation time.

The report should show service, attachment, MAC, all exact addresses, default
policy, allowed peers/protocols/ports, infrastructure exceptions, and rule origin.
This makes the generated security boundary reviewable without reading nft code.

## 9. Required validation before deployment

Use NixOS VM integration tests with the actual bridge/VLAN layout and kernel,
not only `nft --check` or evaluation:

- Allowed request/reply works; an unsolicited reverse connection fails.
- Same-host same-VLAN A-to-B cannot bypass filtering; A allow/B deny still drops.
- Host/container traffic, cross-VLAN routing and applicable NAT paths are covered.
- Both IPv4 and IPv6 enforce the same intended policy, with exactly one configured
  IPv6 prefix per VLAN and attachment-scoped link-local addresses.
- MAC/IP spoofing, forged ARP/NA/RA, rogue DHCP and VLAN tag injection fail.
- A multihomed container cannot use another attachment to bypass a rule.
- Necessary DAD, SLAAC, DHCP, PMTU and neighbour discovery still work.
- IPv6 extension headers and fragments do not bypass transport restrictions.
- Missing inventory, invalid reload and firewall restart/stop never expose a
  temporarily unrestricted container attachment.
- Previously allowed sessions stop after permission removal or audit-to-enforce.
- Unrelated host SSH/management traffic remains reachable.
- Prefix renumbering works without opening access to an entire VLAN.

Implement and validate the identity/control-plane guards together with the first
enforced policy. Deferring them would leave address-based service permissions
vulnerable to impersonation.
