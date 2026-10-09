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
  cfg = config.${namespace}.hardware.spindown;
in
{
  options.${namespace}.hardware.spindown = with types; {
    enable = mkBoolOpt false "Whether or not to spin down hard disks on a schedule";
    disks = mkOpt (listOf str) [ ] "Disks to spin down, as /dev/disk/by-id paths";
    onCalendar = mkOpt str "*-*-* 05:00:00" "When to spin down the disks";
  };

  config = mkIf cfg.enable {
    systemd.services.spindown = {
      description = "Spin down hard disks";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = map (disk: "${pkgs.hdparm}/bin/hdparm -y ${disk}") cfg.disks;
      };
    };

    systemd.timers.spindown = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.onCalendar;
    };

    systemd.services.spindown-notify = {
      description = "Notify when hard disks spin down or up";
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        coreutils
        curl
        hdparm
        jq
      ];
      script = ''
        credentials=${config.sops.secrets.alerts-pushover.path}
        declare -A last

        while true; do
          changes=""
          for disk in ${concatStringsSep " " cfg.disks}; do
            if hdparm -C "$disk" | grep -q standby; then
              state="spun down"
            else
              state="spun up"
            fi
            if [ -n "''${last[$disk]:-}" ] && [ "''${last[$disk]}" != "$state" ]; then
              changes+="$(basename "$disk") $state"$'\n'
            fi
            last[$disk]=$state
          done

          if [ -n "$changes" ]; then
            curl --fail --silent --show-error --retry 3 \
              --form-string "token=$(jq -r .token "$credentials")" \
              --form-string "user=$(jq -r .user "$credentials")" \
              --form-string "title=${config.networking.hostName}: disks" \
              --form-string "message=$changes" \
              https://api.pushover.net/1/messages.json || true
          fi

          sleep 60
        done
      '';
      serviceConfig.Restart = "always";
    };
  };
}
