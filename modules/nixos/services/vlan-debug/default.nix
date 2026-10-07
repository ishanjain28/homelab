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
        MemoryMax = "1G";
        TasksMax = 512;
      };

      containerConfig = {
        environment.systemPackages = mkForce (
          with pkgs;
          [
            bashInteractive
            bind
            coreutils
            curl
            ethtool
            fish
            git
            iftop
            inetutils
            iperf3
            iproute2
            iptraf-ng
            iputils
            jq
            kitty.terminfo
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
          ]
        );
        i18n = {
          defaultLocale = "en_US.UTF-8";
          supportedLocales = [
            "en_US.UTF-8/UTF-8"
            "en_IN/UTF-8"
          ];
        };

        security.sudo.extraRules = [
          {
            users = [ "ishan" ];
            commands = [
              {
                command = "ALL";
                options = [ "NOPASSWD" ];
              }
            ];
          }
        ];

        security.wrappers.ping = {
          source = "${pkgs.iputils}/bin/ping";
          owner = "root";
          group = "root";
          capabilities = "cap_net_raw+ep";
        };

        security.wrappers.traceroute = {
          source = "${pkgs.traceroute}/bin/traceroute";
          owner = "root";
          group = "root";
          capabilities = "cap_net_raw+ep";
        };

        services.openssh = enabled // {
          inherit (ssh) package;
          openFirewall = true;
          generateHostKeys = true;
          settings = {
            PasswordAuthentication = mkForce false;
            PermitRootLogin = "prohibit-password";
            X11Forwarding = false;
          };
        };

        users = {
          mutableUsers = false;
          defaultUserShell = pkgs.fish;
          groups.ishan.gid = 1000;
          users.ishan = {
            isNormalUser = true;
            uid = 1000;
            group = "ishan";
            extraGroups = [ "wheel" ];
            createHome = true;
            home = "/home/ishan";
            homeMode = "700";
            useDefaultShell = true;
            hashedPassword = config.users.users.ishan.hashedPassword;
            openssh.authorizedKeys.keys = ssh.keys;
          };
        };

        programs.fish = enabled // {
          interactiveShellInit = fishKeyBindings;
        };

        environment.shells = with pkgs; [
          bashInteractive
          fish
        ];
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
        endpoints.ssh.port = 22;
        logging = disabled;
      })
    ) vlanIds
  );

  config = mkMerge (map mkDebugContainer vlanIds);
}
