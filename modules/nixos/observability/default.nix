{
  config,
  inputs,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  registry = config.system.homelab.registry;
  allServices = registry.services;
  enabledServices = filterAttrs (_name: service: service.enable) allServices;
  logging = config.${namespace}.logging;
  loggedServices = filterAttrs (_name: service: service.enable && service.logging.enable) allServices;
  metrics = config.${namespace}.metrics;

  intelGpuSample = pkgs.writeShellScript "intel-gpu-sample" ''
    ${pkgs.coreutils}/bin/timeout 6 ${pkgs.intel-gpu-tools}/bin/intel_gpu_top -c -s 2000 | ${pkgs.gnused}/bin/sed -n 3p
  '';

  intelGpuTelegrafConfig = (pkgs.formats.toml { }).generate "telegraf-intel-gpu.toml" {
    agent = {
      interval = "30s";
      flush_interval = "30s";
    };
    inputs.exec = [
      {
        commands = [ "${intelGpuSample}" ];
        timeout = "10s";
        name_override = "intel_gpu";
        data_format = "csv";
        csv_header_row_count = 0;
        csv_column_names = [
          "frequency_requested_mhz"
          "frequency_actual_mhz"
          "interrupts_per_s"
          "rc6_pct"
          "power_gpu_w"
          "power_package_w"
          "render_busy_pct"
          "render_sema_pct"
          "render_wait_pct"
          "blitter_busy_pct"
          "blitter_sema_pct"
          "blitter_wait_pct"
          "video_busy_pct"
          "video_sema_pct"
          "video_wait_pct"
          "video_enhance_busy_pct"
          "video_enhance_sema_pct"
          "video_enhance_wait_pct"
        ];
        fieldinclude = [
          "frequency_actual_mhz"
          "power_gpu_w"
          "render_busy_pct"
          "video_busy_pct"
          "video_enhance_busy_pct"
        ];
      }
    ];
    outputs.influxdb_v2 = [
      {
        urls = [ metrics.victoriaMetricsUrl ];
        bucket = "telegraf";
        organization = "homelab";
        token = "";
      }
    ];
  };
  vethServiceMap = listToAttrs (
    concatLists (
      mapAttrsToList (
        name: service: map (vlan: nameValuePair (mkContainerVethName name vlan) name) service.vlans
      ) enabledServices
    )
  );

  serviceLokiPushUrl =
    name: service:
    let
      configuredVlans = filter (vlan: hasAttr (toString vlan) logging.lokiPushUrls) service.vlans;
    in
    if configuredVlans == [ ] then
      throw "No Loki push URL configured for ${name} on VLANs ${concatMapStringsSep ", " toString service.vlans}"
    else
      logging.lokiPushUrls.${toString (head configuredVlans)};

  hostLokiPushUrl =
    logging.lokiPushUrls.${toString logging.hostVlan}
    or (throw "No Loki push URL configured for host VLAN ${toString logging.hostVlan}");

  fileSourceConfig =
    name: files:
    optionalString (files != [ ]) ''
      local.file_match "logs" {
        path_targets = [
          ${concatMapStringsSep "\n" (
            path: ''{ "__path__" = ${builtins.toJSON path}, "container" = ${builtins.toJSON name}, "source" = "file" },''
          ) files}
        ]
      }

      loki.source.file "logs" {
        targets    = local.file_match.logs.targets
        forward_to = [loki.write.local.receiver]
      }
    '';

  alloyConfig = name: lokiPushUrl: files: ''
    logging {
      level = "warn"
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        regex         = "([a-zA-Z0-9_.@-]+\\.service)"
        target_label  = "unit"
      }

      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "priority"
      }

      rule {
        action = "labeldrop"
        regex  = "syslog_identifier|job|service_name"
      }
    }

    loki.source.journal "systemd" {
      forward_to    = [loki.write.local.receiver]
      relabel_rules = loki.relabel.journal.rules
      labels        = {container = "${name}", source = "journald"}
      max_age       = "24h"
    }

    ${fileSourceConfig name files}

    loki.write "local" {
      endpoint {
        url = "${lokiPushUrl}"
      }
    }
  '';

  fleet = inputs.self.lib.homelabRegistry;
  serviceEndpoints = mapAttrsToList (
    _id: srv:
    let
      inherit (srv) monitor;
      inherit (monitor)
        endpoint
        group
        protocol
        path
        conditions
        ;
      inherit (monitor) name;
      inherit (fleet.hosts.${srv.host}) domain;
      defaultAddress = if domain != "" then "${srv.name}.${domain}" else srv.name;
      address = if monitor.address != "" then monitor.address else defaultAddress;
      port = srv.endpoints.${endpoint}.port;
      url =
        if protocol == "http" || protocol == "https" then
          "${protocol}://${address}:${toString port}${path}"
        else
          "${protocol}://${address}:${toString port}";
    in
    {
      inherit name group url;
      inherit (monitor) interval alerts;
      inherit conditions;
    }
  ) (filterAttrs (_id: srv: srv.monitor.enable) fleet.services);

  invalidMonitorEndpoints = mapAttrsToList (serviceName: srv: "${serviceName}:${toString srv.monitor.endpoint}") (
    filterAttrs (
      _name: srv: srv.monitor.enable && (srv.monitor.endpoint == null || !(hasAttr srv.monitor.endpoint srv.endpoints))
    ) enabledServices
  );

  gatusSettings.endpoints = serviceEndpoints;
in
{
  options.${namespace} = {
    logging = {
      enable = mkBoolOpt false "Whether to collect homelab logs with Alloy and push them to Loki.";
      lokiPushUrls = mkOpt (types.attrsOf types.nonEmptyStr) {
        # Eventually, I either want a v6 only auto derived addresses here or maybe just DNS.
        "50" = "http://10.0.50.23:3100/loki/api/v1/push";
        "70" = "http://10.0.70.11:3100/loki/api/v1/push";
        "99" = "http://10.0.99.29:3100/loki/api/v1/push";
      } "Loki push API URLs keyed by VLAN.";
      hostVlan = mkOpt types.ints.positive 99 "VLAN the host itself is reachable on; selects the host's Loki push URL.";
    };

    metrics = {
      enable = mkBoolOpt false "Whether to enable metrics collection.";
      victoriaMetricsUrl = mkOpt types.nonEmptyStr "http://10.0.50.21:8428" "VictoriaMetrics URL";
      intelGpu.enable = mkBoolOpt false "Whether to collect Intel GPU video engine, frequency and power metrics on this host.";
    };
  };

  config = mkMerge [
    {
      assertions = [
        {
          assertion = invalidMonitorEndpoints == [ ];
          message = "Monitored services reference missing endpoints: ${concatStringsSep ", " invalidMonitorEndpoints}";
        }
      ];
    }

    (mkIf logging.enable {
      services.alloy = enabled // {
        extraFlags = [
          "--disable-reporting"
          "--server.http.enable-pprof=false"
        ];
      };

      systemd.services.alloy.serviceConfig.SupplementaryGroups = mkAfter [ "adm" ];

      environment.etc."alloy/config.alloy".text = alloyConfig "host" hostLokiPushUrl [ ];

      containers = mapAttrs (name: service: {
        config = {
          services.alloy = enabled // {
            extraFlags = [
              "--disable-reporting"
              "--server.http.enable-pprof=false"
            ];
          };

          systemd.services.alloy.serviceConfig = {
            SupplementaryGroups = mkAfter [
              "adm"
              "systemd-journal"
            ];
          }
          // optionalAttrs (service.logging.files != [ ]) {
            DynamicUser = mkForce false;
            User = service.runtimeUser.name;
            Group = service.runtimeUser.group;
          };

          environment.etc."alloy/config.alloy".text = alloyConfig name (serviceLokiPushUrl name service) service.logging.files;
        };
      }) loggedServices;
    })

    (mkIf metrics.enable {
      # Host-only: reads host /proc and /sys directly, and walks each
      # container's cgroup from the outside (machine.slice/container@<name>.service),
      # so it covers host and per-service CPU/mem/disk/net/temp without an
      # agent inside every container.
      services.telegraf = enabled // {
        extraConfig = {
          agent = {
            interval = "30s";
            flush_interval = "30s";
          };

          inputs = {
            system = [
              {
                include = [
                  "cpus"
                  "load"
                  "uptime"
                ];
              }
            ];
            cpu = [
              {
                percpu = false;
                totalcpu = true;
                collect_cpu_time = false;
                report_active = false;
              }
            ];
            mem = [ { } ];
            disk = [
              {
                ignore_fs = [
                  "tmpfs"
                  "devtmpfs"
                  "overlay"
                  "squashfs"
                  "iso9660"
                ];
              }
            ];
            diskio = [ { } ];
            net = [ { } ];
            sensors = [ { } ];
            smart = [
              {
                path_smartctl = "${pkgs.smartmontools}/bin/smartctl";
                path_nvme = "${pkgs.nvme-cli}/bin/nvme";
                interval = "45s";
              }
            ];
            cgroup = [
              {
                paths = [ "/sys/fs/cgroup/machine.slice/container@*.service" ];
                files = [
                  "cpu.stat"
                  "memory.current"
                  "memory.max"
                  "memory.stat"
                  "memory.swap.current"
                  "pids.current"
                ];
              }
            ];
          };

          processors.enum = [
            {
              mapping = [
                {
                  tags = [ "interface" ];
                  dest = "service";
                  value_mappings = vethServiceMap;
                }
              ];
            }
          ];

          processors.regex = [
            {
              tags = [
                {
                  key = "path";
                  pattern = ".*container@(.+)\\.service$";
                  replacement = "$\{1}";
                  result_key = "service";
                }
              ];
            }
          ];

          outputs.influxdb_v2 = [
            {
              urls = [ metrics.victoriaMetricsUrl ];
              bucket = "telegraf";
              organization = "homelab";
              token = "";
            }
          ];
        };
      };

      # The sensors input execs `sensors` from lm_sensors via $PATH.
      systemd.services.telegraf.path = [ pkgs.lm_sensors ];

      # smartctl/nvme need raw device access: `disk` group for SATA/SAS SG_IO,
      # CAP_SYS_ADMIN/CAP_SYS_RAWIO for NVMe admin passthrough commands.
      systemd.services.telegraf.serviceConfig = {
        SupplementaryGroups = [ "disk" ];
        AmbientCapabilities = [
          "CAP_SYS_ADMIN"
          "CAP_SYS_RAWIO"
        ];
      };
    })

    (mkIf (metrics.enable && metrics.intelGpu.enable) {
      systemd.services.telegraf-intel-gpu = {
        description = "Telegraf Intel GPU collector";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${getExe pkgs.telegraf} --config ${intelGpuTelegrafConfig}";
          DynamicUser = true;
          AmbientCapabilities = [ "CAP_PERFMON" ];
          CapabilityBoundingSet = [ "CAP_PERFMON" ];
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };
    })

    {
      # Gatus runs in its dedicated nspawn container, never directly on the host.
      services.gatus = disabled // {
        settings = gatusSettings;
      };
    }
  ];
}
