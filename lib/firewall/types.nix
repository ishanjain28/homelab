{ lib }:
with lib;
let
  opt =
    type: default: description:
    mkOption { inherit type default description; };
  selector = types.submodule {
    options = {
      service = opt (types.nullOr types.str) null "Canonical or host-qualified service name.";
      attachment = opt (types.nullOr types.str) null "Destination attachment (VLAN ID or named network).";
      host = opt (types.nullOr types.str) null "Named inventory host.";
      group = opt (types.nullOr types.str) null "Named address group.";
      cidrs = opt (types.listOf types.str) [ ] "Explicit IPv4/IPv6 CIDRs.";
    };
  };
  rule = types.submodule {
    options = {
      via = opt (types.nullOr types.str) null "Source attachment; required for multihomed services.";
      to = mkOption {
        type = selector;
        description = "Destination selector.";
      };
      endpoint = opt (types.nullOr types.str) null "Destination service endpoint.";
      protocol = opt (types.enum [
        "tcp"
        "udp"
        "icmp"
        "icmpv6"
      ]) "tcp" "IP transport.";
      ports = opt (types.listOf types.port) [ ] "Destination ports; empty requires allPorts.";
      allPorts = opt types.bool false "Explicitly permit all transport ports.";
      icmpTypes = opt (types.listOf (types.ints.between 0 255)) [ ] "Permitted ICMP request types.";
    };
  };
  ingress = types.submodule {
    options = {
      via = opt (types.nullOr types.str) null "Listening attachment; required when multihomed.";
      from = opt (types.listOf selector) [ ] "Allowed peers for this endpoint.";
    };
  };
in
{
  inherit selector rule ingress;
  policy = types.submodule {
    options = {
      mode = opt (types.enum [
        "off"
        "audit"
        "enforce"
      ]) "off" "Host policy rollout mode.";
      ingress = opt (types.attrsOf ingress) { } "Incoming grants keyed by local endpoint.";
      egress = opt (types.listOf rule) [ ] "Outgoing grants.";
      infrastructure = opt (types.listOf types.str) [ ] "Explicit inventory dependency profiles (or database).";
    };
  };
}
