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
  cfg = srv.novnc;
  webRoot = pkgs.runCommand "novnc-web" { } ''
    cp -r ${pkgs.novnc}/share/webapps/novnc "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/vnc.html" "$out/vnc_lite.html" \
      --replace-fail '<title>noVNC</title>' ${escapeShellArg "<title>${escapeXML cfg.vm}</title>"}
    substituteInPlace "$out/app/ui.js" \
      --replace-fail 'const PAGE_TITLE = "noVNC";' 'const PAGE_TITLE = document.title;' \
      --replace-fail 'document.title = e.detail.name + " - " + PAGE_TITLE;' 'document.title = PAGE_TITLE;'
  '';
  consoleDir = "/run/vm-console";
in
{
  options.${namespace}.services.novnc =
    mkServiceOptions {
      name = "novnc";
      description = "Browser console for a virtual machine";
      endpoints.web.port = 6080;
    }
    // {
      vm = mkOption {
        type = types.nonEmptyStr;
        description = "Virtual machine on this host whose console is served.";
      };
    };

  config = mkIf cfg.enable (mkMerge [
    {
      ${namespace}.vms.${cfg.vm}.consoleGid = containerUidOffset + cfg.runtimeId;

      containers.novnc.bindMounts.${consoleDir} = {
        hostPath = "/run/vms/${cfg.vm}/console";
        isReadOnly = false;
      };
    }

    (mkSingleServiceContainer {
      service = cfg;

      resources = {
        CPUQuota = "100%";
        MemoryMax = "256M";
        TasksMax = 64;
      };

      command = "${pkgs.python3Packages.websockify}/bin/websockify --web ${webRoot} --unix-target ${consoleDir}/vnc.sock --heartbeat 30 [::]:${toString cfg.networking.endpoints.web.port}";
    })
  ]);
}
