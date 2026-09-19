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
  cfg = srv.qbittorrent;
  environmentFile = "/run/container-secrets/qbittorrent.env";
  profileDir = "/var/lib/qbittorrent";
  portEnvFile = "/run/pia/env";
  piaCa = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/pia-foss/manual-connections/a1412dbe2ca41edbb79c766bc475335cb6cb13ad/ca.rsa.4096.crt";
    hash = "sha256-Mumx0UM+qXYU8qFMbjWOP1fAVwzJ9rLugSaZumlsZqs=";
  };
  piaVpn = pkgs.writeShellApplication {
    name = "pia-vpn";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      iproute2
      iputils
      jq
      wireguard-tools
    ];
    text = builtins.readFile ./pia-vpn.sh;
  };
in
{
  options.${namespace}.services.qbittorrent =
    mkServiceOptions {
      name = "qbittorrent";
      description = "qBittorrent behind a PIA WireGuard tunnel";
      endpoints.web.port = 8080;
      monitor = enabled // {
        endpoint = "web";
        protocol = "http";
      };
    }
    // (with types; {
      vpnRegion = mkOpt nonEmptyStr "sg" "PIA region id; must support port forwarding.";
      lanNetworks = mkOpt (listOf nonEmptyStr) [
        "10.0.0.0/8"
      ] "Networks qBittorrent may reach outside the tunnel (web UI clients, *arr apps).";
    });

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    package = pkgs.qbittorrent-nox;
    exec = "/bin/qbittorrent-nox --confirm-legal-notice --profile=${profileDir} --webui-port=${toString cfg.endpoints.web.port} --torrenting-port=\${PIA_PORT}";
    hardeningProfile = "strict";
    serviceConfig = {
      EnvironmentFile = portEnvFile;
      StateDirectory = "qbittorrent";
      TimeoutStopSec = "60s";
    };
    secrets.env = {
      file = "secrets/qbittorrent.env";
      format = "dotenv";
      mountPath = environmentFile;
    };
    resources = {
      CPUQuota = "400%";
      MemoryMax = "2G";
      TasksMax = 1024;
    };

    containerConfig = {
      networking.firewall.trustedInterfaces = [ "wg0" ];

      # Drop anything the qbittorrent user sends that is not going to wg0 or the LAN.
      # WireGuard encrypts packets in place, so the encrypted copy leaving eth50 still
      # carries qbittorrent's socket owner; it is recognised by the fwmark instead.
      networking.nftables = enabled // {
        tables.pia-killswitch = {
          family = "inet";
          content = ''
            chain output {
              type filter hook output priority filter; policy accept;
              meta mark 51820 accept
              meta skuid ${toString cfg.runtimeId} oifname != { "lo", "wg0" } ip daddr != { ${concatStringsSep ", " cfg.lanNetworks} } counter drop
              meta skuid ${toString cfg.runtimeId} oifname != { "lo", "wg0" } meta nfproto ipv6 counter drop
            }
          '';
        };
      };

      systemd.services.qbittorrent = {
        wantedBy = mkForce [ ];
        bindsTo = [ "pia-vpn.service" ];
      };

      systemd.paths.qbittorrent = {
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathExists = portEnvFile;
      };

      systemd.services.pia-vpn = {
        description = "PIA WireGuard tunnel with port forwarding";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        environment = {
          PIA_REGION = cfg.vpnRegion;
          PIA_CA = "${piaCa}";
        };
        serviceConfig = getNspawnHardeningProfile "default" // {
          EnvironmentFile = environmentFile;
          ExecStart = "${piaVpn}/bin/pia-vpn";
          RuntimeDirectory = "pia";
          Restart = "always";
          RestartSec = "15s";
          CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
        };
        unitConfig.StartLimitIntervalSec = 0;
      };
    };
  });
}
