# Service firewall

The implementation is opt-in. No production inventory entries, service policies,
DHCP reservations or live firewall changes are installed by this change.

## Populate the inventory

`default.nix` describes connected networks, trusted infrastructure, named hosts
and address groups. VLAN keys are strings. Each VLAN has exactly one IPv6 /64;
the prefix need not resemble the VLAN number. These are **example values**:

```nix
{
  networks."50" = {
    ipv6Prefix = "2a0a:6040:4004:50::/64";
    ipv4Prefix = "10.0.50.0/24";
    routers = [
      { mac = "02:00:00:00:00:01"; ipv6 = "fe80::1"; }
    ];
    dhcpServers = [
      { mac = "02:00:00:00:00:01"; ipv4 = "10.0.50.1"; }
    ];
  };
  hosts.internal-dns = [ "10.0.99.2" ];
  groups.admin-devices = [ "10.0.10.7/32" "2001:db8::7/128" ];
  infrastructure.dns.egress = [
    { to.host = "internal-dns"; protocol = "udp"; ports = [ 53 ]; }
    { to.host = "internal-dns"; protocol = "tcp"; ports = [ 53 ]; }
  ];
}
```

Use the router/DHCP identities as actually observed on the container network,
including a relay's identity where applicable. Empty router/server lists do not
permit RA/DHCP responses. DHCP clients may broadcast discovery; this does not
permit ordinary services to operate DHCP servers.

`ipv4.json` is unencrypted and contains service → attachment → IPv4:

```json
{
  "seerr": { "50": "10.0.50.24" },
  "caddy": { "50": "10.0.50.10", "140": "10.0.140.10" }
}
```

The addresses above are illustrative, not new assignments. Configure matching
DHCP reservations/static addresses independently. A mismatched lease will be
blocked in enforce mode. Missing IPv4 inventory is an evaluation error for a
managed attachment. The file defaults to an empty map to avoid guessing leases.

Use a host-qualified key such as `annapurna/caddy` to disambiguate service names;
that entry takes precedence over the short name. Service selectors accept the
same names. They must resolve uniquely. Address collisions on a connected
network are rejected for inventoried identities.

Standard groups are `rfc1918`, `ula`, `cgnat`, `link-local`, `multicast` and
`homelab`. `homelab` contains all inventory IPv4 and IPv6 network prefixes,
including public IPv6. Define other groups as CIDR lists. A group never grants
access by itself. There is deliberately no `internet = !rfc1918` shorthand:
that would include your public IPv6 internal networks.

## Configure a service

Enable the host integration and add a service policy, initially in audit mode:

```nix
homelab.firewall.enable = true;

homelab.services.seerr.networkPolicy = {
  mode = "audit";
  ingress.web.from = [
    { service = "annapurna/caddy"; attachment = "50"; }
    { group = "admin-devices"; }
  ];
  egress = [
    {
      to.service = "annapurna/postgresql-home-primary";
      protocol = "tcp";
      ports = [ 5432 ];
    }
    {
      to.host = "radarr-normal";
      protocol = "tcp";
      ports = [ 7878 ];
    }
  ];
  infrastructure = [ "dns" ];
};
```

Add `radarr-normal` to inventory hosts before using this example. This is not a
complete Seerr policy: metadata providers, Sonarr, notification providers and
other enabled integrations need grants too.

- `off` installs no service policy. This is the default.
- `audit` counts/logs would-be denials but lets traffic continue. It provides no
  isolation. The existing guest firewall still applies.
- `enforce` denies unlisted application traffic in both directions.
- `ingress.<endpoint>` uses existing listener ports/transports. Its `from` list
  accepts service, host, group or explicit `cidrs` selectors.
- `egress` uses `to` plus either a service `endpoint` or explicit `protocol` and
  `ports`. Use `allPorts = true` only for an intentional all-ports grant.
- For multihomed services, specify `via = "50"` on each grant and
  `attachment = "50"` on a multihomed peer selector. Addresses are never silently
  unioned across attachments.
- Outgoing ICMP echo is supported with `protocol = "icmp"; icmpTypes = [ 8 ];`
  or `protocol = "icmpv6"; icmpTypes = [ 128 ];`. Necessary related ICMP errors
  are handled separately. Incoming application grants currently use TCP/UDP
  listener endpoints.
- Replies must match the corresponding reverse grant and established conntrack
  direction. There is no blanket established-connection bypass.
- Both services must permit an initial connection. Allowing Seerr to reach a
  managed PostgreSQL service does not automatically open PostgreSQL ingress.

## Dependency profiles

`infrastructure` is an explicit list of profile names, not automatic LAN access.
Each inventory profile can contain `egress` grants and endpoint-keyed `ingress`
grants using the same syntax as a service policy. Set `via` in a profile when it
is used by multihomed services; use separate profiles for different attachments.

Use profiles for DNS, logging and monitoring with the actual destination/collector
addresses and ports. For example, logging can grant an outgoing Loki endpoint,
and monitoring can grant an incoming named metrics endpoint from one collector.
Nothing attempts to infer addresses from encrypted application configurations
or to resolve hostnames during Nix evaluation.

The reserved `database` profile derives the PostgreSQL instance from the service's
existing `database.instance` metadata and uses that instance's named `postgres` endpoint. Missing metadata or
ambiguous multihomed instances fail evaluation; use an explicit rule in that case.
The server still needs a corresponding ingress policy.

## Untagged containers

Native nspawn containers such as Manaslu's can use an explicit declaration:

```nix
homelab.firewall.extraServices.vaultwarden = {
  attachments.services = {
    interface = "ve-vaultwarden";
    mac = "02:00:00:00:00:03";
    network = "delhi-services";
  };
  endpoints.web = { port = 8222; transport = "tcp"; expose = true; };
  networkPolicy.mode = "audit";
};
containers.vaultwarden.localMacAddress = "02:00:00:00:00:03";
```

Add `networks.delhi-services.ipv4Prefix` and
`ipv4.json` entry `"vaultwarden": { "services": "172.17.0.3" }`.
An untagged IPv4-only network may omit `ipv6Prefix`; it still has a derived
link-local identity. If adding IPv6, configure the guest to use the declared MAC
and EUI-64 address as well. These explicit declarations do not rewrite guest
network configuration. There is no invented VLAN 0.

The module checks for undeclared nspawn attachments and requires a matching
explicit MAC for native containers. Native host BIRD/WireGuard and other host
processes remain governed by the host firewall, not container veth policy.

## Inspect and roll out

After building the host configuration, the resulting system includes:

- `/etc/homelab/firewall.json`: effective addresses, permissions and grant origins.
- `/etc/homelab/firewall.nft`: generated service table for review.

On a deployed audit host, inspect `sudo nft list table bridge homelab_services`
and `journalctl -k -g hlfw`. Denials have rate-limited logs and counters. Review
what an application actually needs; do not blindly allow every observed request.
Set an individual service to `enforce` after completing its inventory and policy.

Updates replace the owned table atomically. The current policy is checked on
both original packets and replies, so removal of a grant also blocks established
sessions without globally clearing conntrack. Failed nft transactions retain
previous rules. Audit-to-enforce follows the same current-policy checks.

Managed containers require and bind to `nftables.service`. Stopping the firewall
unit stops those containers, and its stop action retains installed rules. This
intentionally also retains other nftables-owned tables during a stop/restart.
A subsequent start/reload replaces tables using the NixOS transaction. A manual
firewall stop stops managed containers; start them again explicitly after the
firewall is active. A restart propagates to dependent containers, ordered after
the firewall has started. Normal configuration updates use reload. Explicit
configuration changes disabling a policy remove that protection. Do not manually
flush rules or enable flow offload for managed traffic.

## Boundaries and conservative defaults

- A container's host veth, MAC, IPv4 address and EUI-64 IPv6 addresses define its
  identity. Other known local service ports cannot claim an enforced identity,
  even when their own policy is off. Unknown VM ports and external devices still
  require trusted L2 networking/switch protections; IP identity is not authentication.
- Source validation precedes bridge learning. Egress runs in bridge prerouting
  after conntrack and before host-input VLAN encapsulation; ingress runs on
  forwarding/output to the container port. ARP/ND impersonation, rogue RA and
  DHCP server traffic are blocked. VLAN access-port membership remains essential;
  residual nested VLAN headers are denied, and bridge filtering prevents crossing
  into an unauthorized VLAN.
- Outgoing IPv6 fragments are conservatively denied before reassembly, including
  fragmented ND. Ordinary IPv6 TCP should use PMTU rather than source fragmentation.
  Applications needing fragmented IPv6 datagrams require future targeted support.
- The qBittorrent VPN stays inside its container. Give explicit outer VPN/bootstrap
  permissions and separate LAN permissions. The host cannot filter encrypted inner
  destinations; the VPN's internal-network exclusion remains its responsibility.
- A Caddy peer permission identifies Caddy, not its original HTTP client. Apply
  client restrictions at the proxy too. Broad HTTPS/proxy access can relay traffic.
- Changing a VLAN prefix replaces derived addresses. Coordinate the RA change;
  stale old-prefix addresses are blocked and a transition may interrupt connectivity.

## Tests

```sh
nix build path:.#checks.x86_64-linux.firewall
nix build path:.#checks.x86_64-linux.firewall-vm
```

`path:.` includes new files before they are staged in Git. Once tracked, the usual
`.#checks...` references work too.

The VM test runs the same disposable namespace packet harness used during
implementation, against the pinned NixOS kernel. It uses software emulation so
KVM is not required. Unit/module checks cover address derivation, invalid or
missing inventory, rule validation and firewall/container unit dependencies.
The packet harness checks allowed replies, same-VLAN denials, spoofing, control
packets, existing-connection revocation, atomic failure and audit transitions.
