{
  inputs,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  hostName = "manaslu";
  backups = import ./backups.nix;
  volumes = import ./volumes.nix;
  workloads = import ./workloads.nix { inherit lib namespace; };
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  homelab = {
    profiles.server = enabled;
    inherit backups;
    inherit volumes;
    services = workloads;
    logging.enable = mkForce false;

    shares.dl = {
      hostPath = "/home/ishan/dl";
      gid = 30393;
      readOnly = true;
    };

    hardware.networking = enabled // {
      inherit hostName;
      domain = "direct.del.ishanjain.me";
      links = {
        "10-public" = {
          matchConfig.MACAddress = "56:00:04:5a:55:50";
          linkConfig.Name = "eth0";
        };
      };

      networks = {
        "20-public" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = true;
            IPv6PrivacyExtensions = false;
            LinkLocalAddressing = "ipv6";
            IPv6LinkLocalAddressGenerationMode = "eui64";
          };
          ipv6AcceptRAConfig = {
            Token = "eui64";
            DHCPv6Client = false;
          };
        };
      };

      tcpPorts = [
        22
        40000
      ];

    };
  };

  networking = {
    nameservers = [
      "127.0.0.1"
      "1.1.1.1"
    ];
    firewall = {
      filterForward = true;
      extraForwardRules = ''
        iifname { "wg-home-vpn", "wg-ipv6" } accept
        oifname { "wg-home-vpn", "wg-ipv6" } accept
      '';
      # Loose validation is needed for the existing routed WireGuard prefixes.
      checkReversePath = "loose";
      extraInputRules = ''
        tcp dport 10080 ct status dnat accept
        meta l4proto { tcp, udp } th dport 10443 ct status dnat accept
        meta l4proto { tcp, udp } th dport 8853 ct status dnat accept
        iifname "wg-home-vpn" meta l4proto { tcp, udp } th dport 5353 ct status dnat accept
      '';
      interfaces = {
        wg-home-vpn.allowedTCPPorts = [
          2019
          5432
          25000
        ];
      };
    };
  };

  # Caddy and AdGuard Home run unprivileged, so they listen on high ports and the host
  # redirects the standard ports there. Clients keep their source address; the services
  # bind all addresses because redirect rewrites the destination to the interface's primary address.
  networking.nftables.tables.port-redirect = {
    family = "inet";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat;
        fib daddr type local tcp dport 80 redirect to :10080
        fib daddr type local meta l4proto { tcp, udp } th dport 443 redirect to :10443
        fib daddr type local meta l4proto { tcp, udp } th dport 53 redirect to :5353
        fib daddr type local meta l4proto { tcp, udp } th dport 853 redirect to :8853
      }
      chain output {
        type nat hook output priority dstnat;
        fib daddr type local tcp dport 80 redirect to :10080
        fib daddr type local meta l4proto { tcp, udp } th dport 443 redirect to :10443
        fib daddr type local meta l4proto { tcp, udp } th dport 53 redirect to :5353
        fib daddr type local meta l4proto { tcp, udp } th dport 853 redirect to :8853
      }
      # The host's own connections to its public or VPN addresses were redirected to loopback;
      # use a loopback source too, so replies match no matter which address the service answers from.
      chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "lo" ct status dnat meta l4proto { tcp, udp } th dport { 5353, 8853, 10080, 10443 } meta nfproto ipv4 snat ip to 127.0.0.1
        oifname "lo" ct status dnat meta l4proto { tcp, udp } th dport { 5353, 8853, 10080, 10443 } meta nfproto ipv6 snat ip6 to ::1
      }
    '';
  };

  # resolved's mDNS responder binds UDP 5353 and steals queries meant for AdGuard Home.
  services.resolved.settings.Resolve.MulticastDNS = false;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  systemd.services."container@adguardhome" = {
    after = [
      "network-online.target"
      "wg-quick-wg-home-vpn.service"
    ];
    wants = [
      "network-online.target"
      "wg-quick-wg-home-vpn.service"
    ];
  };
  systemd.services."container@postgresql-del-primary" = {
    after = [
      "network-online.target"
      "wg-quick-wg-home-vpn.service"
    ];
    wants = [
      "network-online.target"
      "wg-quick-wg-home-vpn.service"
    ];
  };

  systemd.services."container@znc" = {
    after = [
      "network-online.target"
      "wg-quick-wg-home-vpn.service"
    ];
    wants = [
      "network-online.target"
      "wg-quick-wg-home-vpn.service"
    ];
  };

  environment.systemPackages = [ pkgs.wireguard-tools ];

  users.users.ishan.extraGroups = [ "homelab-share-dl" ];

  sops.secrets.tailscale-auth-key = {
    sopsFile = "${inputs.self}/secrets/tailscale/auth-key";
    format = "binary";
  };

  system.stateVersion = "26.05";
}
