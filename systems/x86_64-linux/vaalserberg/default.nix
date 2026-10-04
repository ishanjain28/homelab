{
  inputs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  hostName = "vaalserberg";
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  homelab = {
    profiles.server = enabled;
    logging.enable = mkForce false;

    services.bird = enabled // {
      passwordSecret = "secrets/vaalserberg/bird.password";
      config = builtins.readFile ./bird.conf;
    };

    hardware.networking = enabled // {
      inherit hostName;
      domain = "direct.ams.ishanjain.me";
      networks = {
        "20-public" = {
          matchConfig.Name = [
            "en*"
            "eth*"
          ];
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

      tcpPorts = [ 22 ];
    };
  };

  sops.secrets.tailscale-auth-key = {
    sopsFile = "${inputs.self}/secrets/tailscale/auth-key";
    format = "binary";
  };

  system.stateVersion = "26.05";
}
