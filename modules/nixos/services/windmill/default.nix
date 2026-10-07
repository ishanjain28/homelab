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
  cfg = config.${namespace}.services.windmill;
  environmentFile = "/run/container-secrets/windmill.env";
  commonEnvironment = {
    JSON_FMT = "true";
    RUST_LOG = "info";
  };
  commonServiceConfig = {
    EnvironmentFile = environmentFile;
    ExecStart = getExe pkgs.${namespace}.windmill;
    LimitNOFILE = 65536;
    PrivateTmp = true;
    Restart = "always";
    RestartSec = "5s";
    TimeoutStopSec = "30s";
  };
in
{
  options.${namespace}.services.windmill = mkServiceOptions {
    name = "windmill";
    description = "Windmill workflow automation platform";
    endpoints.web.port = 5678;
    monitor = enabled // {
      endpoint = "web";
      protocol = "http";
      path = "/api/health/status";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    serviceProfiles.windmill-server = "jit";
    databaseUnits = [
      "windmill-server"
      "windmill-worker"
    ];

    secrets.env = {
      file = "secrets/windmill.env";
      format = "dotenv";
      mountPath = environmentFile;
    };

    resources = {
      CPUQuota = "600%";
      MemoryMax = "12G";
      TasksMax = 8192;
    };

    containerConfig = {
      # Windmill uses uv-managed CPython builds for dependency resolution.
      # Those are generic Linux binaries and need an FHS-compatible dynamic
      # linker inside the otherwise pure NixOS container.
      programs.nix-ld = enabled // {
        libraries = with pkgs; [
          stdenv.cc.cc
          zlib
          openssl
          libffi
          bzip2
          xz
        ];
      };

      systemd.services = {
        windmill-server = {
          description = "Windmill API Server and Web UI";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment = commonEnvironment // {
            MODE = "server";
            PORT = toString cfg.endpoints.web.port;
          };
          serviceConfig = commonServiceConfig // {
            User = cfg.runtimeUser.name;
            Group = cfg.runtimeUser.group;
            StateDirectory = "windmill";
            StateDirectoryMode = "0700";
            WorkingDirectory = "/var/lib/windmill";
          };
        };

        windmill-worker = {
          description = "Windmill Execution Worker";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment = commonEnvironment // {
            MODE = "worker";
            DENO_TLS_CA_STORE = "system,mozilla";
            # Windmill clears the child environment. Forward the library path
            # added by the package wrapper so native Python wheels can find
            # libstdc++ and libgcc at runtime.
            WHITELIST_ENVS = "LD_LIBRARY_PATH";
            # Keep job workspaces and dependency/runtime caches on the
            # persistent, writable systemd state directory instead of /tmp.
            WINDMILL_DIR = "/var/lib/windmill-worker";
          };
          serviceConfig = commonServiceConfig // {
            User = "root";
            Group = "root";
            # Windmill's embedded nsjail profiles require /lib to exist.
            # NixOS does not normally provide it, so expose glibc there only
            # inside the worker's mount namespace.
            BindReadOnlyPaths = [ "${pkgs.glibc}/lib:/lib" ];
            StateDirectory = "windmill-worker";
            StateDirectoryMode = "0700";
            WorkingDirectory = "/var/lib/windmill-worker";
          };
        };
      };
    };
  });
}
