{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  inherit (srv) ssh;
  vlanIds = [
    10
    20
    30
    40
    50
    99
    140
    150
    160
  ];
  mkName = vlan: "vlan${toString vlan}-debug";
  mkDebugContainer =
    vlan:
    let
      name = mkName vlan;
      cfg = srv.${name};
    in
    mkIf cfg.enable (mkServiceContainer {
      service = cfg;

      resources = {
        CPUQuota = "100%";
        MemoryMax = "256M";
        TasksMax = 256;
      };

      containerConfig = {
        environment.systemPackages = with pkgs; [
          bashInteractive
          bind
          curl
          ethtool
          inetutils
          iperf3
          iproute2
          iputils
          jq
          mtr
          netcat-openbsd
          nftables
          nmap
          openssl
          socat
          tcpdump
          traceroute
          wget
          whois
        ];

        services.openssh = enabled // {
          inherit (ssh) package;
          openFirewall = true;
          settings = {
            PasswordAuthentication = false;
            PermitRootLogin = "prohibit-password";
            X11Forwarding = false;
          };
        };

        users.users.root = {
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keys = ssh.keys;
        };
      };
    });
in
{
  options.${namespace}.services = listToAttrs (
    map (
      vlan:
      nameValuePair (mkName vlan) (mkServiceOptions {
        name = mkName vlan;
        description = "VLAN ${toString vlan} debug container";
        port = 22;
        monitor = {
          enable = false;
          protocol = "tcp";
        };
      })
    ) vlanIds
  );

  config = mkMerge (map mkDebugContainer vlanIds);
}
