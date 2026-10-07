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
  cfg = srv.samba;
  configPath = "/run/container-secrets/smb.conf";
  passwordsPath = "/run/container-secrets/smbpasswd";
  usersPath = "/run/container-secrets/users";
in
{
  options.${namespace}.services.samba = mkServiceOptions {
    name = "samba";
    description = "Samba file server";
    endpoints = {
      smb.port = 445;
      wsdd-discovery = {
        port = 3702;
        transport = "udp";
      };
      wsdd-http.port = 5357;
    };
    monitor = enabled // {
      endpoint = "smb";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkSingleServiceContainer {
    service = cfg;
    command = "${pkgs.samba}/sbin/smbd --foreground --no-process-group --configfile=${configPath}";
    serviceProfile = "file-server";

    secrets = {
      config = {
        file = "secrets/samba/smb.conf";
        format = "binary";
        mountPath = configPath;
      };
      passwords = {
        file = "secrets/samba/smbpasswd";
        format = "binary";
        mountPath = passwordsPath;
        mode = "0600";
      };
      users = {
        file = "secrets/samba/users";
        format = "binary";
        mountPath = usersPath;
      };
    };

    resources = {
      CPUQuota = "400%";
      MemoryMax = "2G";
      TasksMax = 1024;
    };

    serviceConfig = {
      User = "root";
      Group = "root";
      Type = "notify";
      NotifyAccess = "all";
      RuntimeDirectory = "samba";
      RuntimeDirectoryMode = "0700";
      TemporaryFileSystem = "/var/log/samba";
    };

    containerConfig = {
      environment.systemPackages = [ pkgs.samba ];

      systemd.services.samba = {
        path = [ pkgs.shadow ];
        preStart = ''
          while IFS=: read -r name groups; do
            id -u "$name" > /dev/null 2>&1 || useradd --system --no-create-home --no-user-group --gid nogroup "$name"
            usermod -G "$groups" "$name"
          done < ${usersPath}
        '';
      };

      services.samba-wsdd = {
        enable = true;
        openFirewall = false;
      };
    };
  });
}
