I’d build a **declarative, default-deny network policy for each service**, compiled into nftables rules on the host. Your existing service declarations and named endpoints are a good foundation.

The important part is enforcing it at the right place. Your containers connect directly to the VLAN-aware `br0` bridge through dedicated veth interfaces. Traffic between containers on the same VLAN can bypass the router. Currently, [lib/services/default.nix](/home/ishan/nix/lib/services/default.nix) opens endpoint ports inside each container, but doesn’t restrict their sources or outbound connections.

**1. Enforce policy outside the containers**

Use host-side nftables **bridge-family filtering**, identifying each container by its host-side veth interfaces. Your existing `mkContainerVethName` already gives those interfaces predictable names.

This covers same-VLAN traffic and keeps the enforcement outside a compromised container. nftables supports bridge filtering and connection tracking. [Bridge filtering documentation](https://wiki.nftables.org/wiki-nftables/index.php/Bridge_filtering)

The rules must cover all three paths:

| Traffic | Policy to enforce |
|---|---|
| Container → external network | Container egress |
| External network → container | Container ingress |
| Container A → container B | A’s egress **and** B’s ingress |
| Container ↔ host itself | Corresponding container policy, plus host firewall |

Cover bridge `input`, `forward`, and `output`; a forward-only implementation misses host/container traffic.

A particularly important implementation detail: permitting A’s egress must not skip B’s ingress check. Compile these as successive checks, with a successful check returning to the caller. Don’t put an early blanket `accept` in the first service chain.

Keep the host’s own management firewall separate. The container-policy table should affect managed container ports, without changing unrelated VM or bridge traffic.

**2. Make endpoints and network permissions separate concepts**

An endpoint describes what a service listens on. It should not automatically mean “every reachable machine may connect.”

I’d aim for an interface like this—**proposed syntax, not existing options**:

```nix
homelab.services.tracearr.networkPolicy = {
  mode = "enforce";

  ingress.app.from = [
    { service = "annapurna/caddy"; }
    { hostGroup = "admin-devices"; }
  ];

  egress.allow = [
    {
      to.service = "annapurna/postgresql-home-primary";
      endpoint = "postgres";
    }
    {
      to.host = "jellyfin";
      protocol = "tcp";
      ports = [ 8096 ];
    }
  ];

  infrastructure = {
    dns = "internal";
    logging = true;
    monitoring = true;
  };
};
```

The semantics should be simple:

- New incoming connections are denied unless permitted for that endpoint.
- New outgoing connections are denied unless permitted.
- Replies to permitted connections are allowed.
- An empty outbound application allowlist means no application-initiated network access beyond the explicitly selected infrastructure permissions.
- Every attached interface is covered, for both IPv4 and IPv6.
- Port lists mean **destination ports**; source-port restrictions are an advanced option.

No separate `internet = false` is needed for ordinary policies: default-deny already provides that. A service gets Internet access only through an explicit outbound allowance.

The enforcement unit here is the **whole container**, including its logging agent and helper processes. Processes sharing a container also share its network permissions. Split them into separate containers if they need different trust boundaries.

**3. Give address sets precise meanings**

Provide built-in address sets and user-defined groups:

| Name | Meaning |
|---|---|
| `rfc1918` | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` |
| `ula` | IPv6 `fc00::/7` |
| `cgnat` | `100.64.0.0/10` |
| `link-local` | IPv4 and IPv6 link-local ranges |
| `multicast` | IPv4 and IPv6 multicast ranges |
| `homelab` | Your actual internal prefixes, including globally addressed IPv6 |
| `admin-devices` | Explicit administrative devices |
| `dns-resolvers` | Approved resolver addresses |

The standardized ranges come from the IANA [IPv4](https://www.iana.org/assignments/iana-ipv4-special-registry/) and [IPv6](https://www.iana.org/assignments/iana-ipv6-special-registry/) registries.

**`rfc1918` must not mean “trusted,” and “not RFC1918” must not mean “Internet.”** Your LAN can contain public IPv6 addresses; private address space can contain untrusted clients. Likewise, the CGNAT range is broader than your own Tailscale devices.

Allow groups to combine other groups and explicit CIDRs, with exclusions if needed. Compile them into separate IPv4 and IPv6 nftables sets. Reject unknown references and circular group definitions during evaluation.

**4. Establish an authoritative host/address inventory**

Your containers currently use DHCP and SLAAC. Stable MAC addresses help, but the service registry does not currently contain authoritative IP addresses.

For reliable rules such as `to.service = "annapurna/postgresql-home-primary"`, add:

- Named hosts and their addresses.
- Service addresses **per VLAN**.
- DHCP reservations or static addresses consistent with that inventory.
- Stable internal IPv6 addresses, or an explicit mechanism for updating delegated prefixes.

I would start with declared addresses and reservations. Avoid resolving arbitrary DNS names while evaluating Nix: that makes policy depend on whichever answer the build machine happened to receive.

Service references should resolve to the declared attachment/address set, not accidentally grant access through every VLAN the destination uses.

Where feasible, bind each managed veth to its expected source MAC and IP addresses. Otherwise, a compromised service could impersonate another permitted source. External source-IP allowlists still depend on anti-spoofing elsewhere in your network; they are not substitutes for authentication.

**5. Generate narrow infrastructure permissions**

Default-deny needs some carefully defined supporting traffic:

- DHCP bootstrap and lease renewal.
- ARP and essential IPv6 neighbor discovery/router discovery.
- Necessary ICMP errors, including path-MTU discovery.
- DNS to approved resolvers, over UDP **and TCP**.
- Logging to the configured Loki endpoint.
- Monitoring from the configured monitoring host.

These should be explicit, inspectable generated rules—not an implicit “allow all LAN traffic” exception. Restrict DHCP-server and router-advertisement behavior so ordinary service containers cannot act as network infrastructure.

Your existing metadata can eliminate repetitive declarations:

- `database.instance` generates client egress to that database endpoint.
- The database’s policy can explicitly permit its declared consumers.
- `logging.enable` generates access to the chosen Loki endpoint.
- `monitor.enable` generates the necessary monitoring connection permissions.

Every generated permission should retain its origin, so you can see *why* it exists. Avoid discovering essential policy by parsing encrypted application configuration; declare the dependency alongside the service instead.

**6. Handle reverse proxies and Internet access deliberately**

For applications behind Caddy, allow application ingress from Caddy and any explicitly permitted direct clients.

But the backend sees **Caddy’s address**, not the original browser’s address. If only certain clients may use an application through Caddy, enforce that restriction at Caddy or its authentication layer too. The backend firewall alone cannot distinguish those clients.

For outbound Internet access, distinguish:

- **No access:** local dependencies only.
- **Destination/port access:** specific addresses and protocols.
- **Domain-restricted web access:** an explicit egress proxy with a destination policy.
- **Broad access:** an intentionally broad exception for workloads that require it.

A DNS name expanded into firewall IP addresses is not a reliable domain security boundary: addresses change and CDNs share them. Similarly, allowing TCP 443 to arbitrary destinations permits much more than software update checks.

“No Internet” also means examining allowed intermediaries. A permitted proxy, recursive DNS server, or application relay can provide indirect external access.

**7. Treat deployment and verification as part of the design**

I would implement this in stages:

1. Add the address inventory, typed policy options, and a readable effective-policy report.
2. Generate rules in an audit mode that counts and rate-limits logs for traffic that would be denied.
3. Test enforcement with network namespaces or NixOS VM tests.
4. Enforce on one simple service, then expand gradually.

The tests need to prove **denial**, not just successful access: same-host container traffic, cross-host traffic, host/container traffic, IPv6, multiple VLANs, spoofed sources, DNS restrictions, and replies to allowed connections.

Load rules atomically, before containers become reachable, and preserve the previous rules if an update fails. Also define what happens to existing connections when access is revoked: an `established` allowance can preserve an old session until its connection-tracking entry expires.

For this repository, I’d add policy options to `mkServiceOptions`, put compilation in a separate `lib/firewall`, and have a host module own the generated nftables tables. **The first implementation should focus on explicit host/service identities, endpoint-based ingress, default-deny egress, dual-stack enforcement, and an effective-policy report.** That gives you a system you can understand and test before adding dynamic domain lists or more elaborate exceptions.
