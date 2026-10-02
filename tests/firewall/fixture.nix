{ lib }:
let
  net = import ../../lib/networking/default.nix { inherit lib; };
  veth =
    name: vlan: "v${builtins.substring 0 9 (builtins.hashString "sha256" "${name}:${toString vlan}")}-${toString vlan}";
  compile = import ../../lib/firewall/compiler.nix {
    inherit lib;
    inherit (net) mkMacAddress;
    mkContainerVethName = veth;
  };
  service = name: interface: mac: networkPolicy: {
    inherit name networkPolicy;
    host = "test";
    attachments."50" = {
      inherit interface mac;
      network = "50";
    };
    endpoints.web = {
      port = 8080;
      transport = "tcp";
      expose = true;
    };
  };
  args = {
    hostName = "test";
    inventory = {
      networks."50" = {
        ipv6Prefix = "fd42:50::/64";
        ipv4Prefix = "10.50.0.0/24";
        routers = [
          {
            mac = "02:00:00:00:00:01";
            ipv6 = "fe80::1";
          }
        ];
        dhcpServers = [
          {
            mac = "02:00:00:00:00:01";
            ipv4 = "10.50.0.1";
          }
        ];
      };
      hosts.router = [
        "10.50.0.1"
        "fd42:50::1"
      ];
      infrastructure.dns.egress = [
        {
          to.host = "router";
          protocol = "udp";
          ports = [ 53 ];
        }
      ];
    };
    ipv4 = {
      a."50" = "10.50.0.2";
      b."50" = "10.50.0.3";
    };
    services = {
      "test/u" = service "u" "pu" "02:00:00:00:00:04" { mode = "off"; };
      "test/a" = service "a" "pa" "02:00:00:00:00:02" {
        mode = "enforce";
        egress = [
          {
            to.service = "b";
            endpoint = "web";
          }
          {
            to.host = "router";
            protocol = "tcp";
            ports = [ 8080 ];
          }
        ];
        ingress.web.from = [ { host = "router"; } ];
        infrastructure = [ "dns" ];
      };
      "test/b" = service "b" "pb" "02:00:00:00:00:03" {
        mode = "enforce";
        ingress.web.from = [ { service = "a"; } ];
      };
    };
  };
in
{
  inherit args compile;
  compiled = compile args;
}
