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
  cfg = config.${namespace}.observability.alerts;
  credentials = config.sops.secrets.alerts-pushover.path;
in
{
  options.${namespace}.observability.alerts = {
    enable = mkEnableOption "Pushover notifications for failed units";
    credentialsSecret =
      mkOpt types.nonEmptyStr "secrets/alerts/pushover.json"
        "Repository-relative SOPS JSON file with the Pushover `token` and `user` keys.";
    sound = mkOpt types.nonEmptyStr "falling" "Pushover sound for failure alerts.";
    unit = mkOption {
      type = types.str;
      readOnly = true;
      default = "notify-failure@%n.service";
      description = "Value to add to a unit's onFailure to get notified when it fails.";
    };
  };

  config = mkIf cfg.enable {
    sops.secrets.alerts-pushover = {
      sopsFile = "${inputs.self}/${cfg.credentialsSecret}";
      format = "json";
      key = "";
    };

    systemd.services."notify-failure@" = {
      description = "Send a Pushover notification that %i failed";
      path = with pkgs; [
        curl
        jq
        systemd
      ];
      scriptArgs = "%i";
      script = ''
        unit=$1
        # Pushover caps messages at 1024 characters.
        log=$(journalctl --unit "$unit" --lines 15 --no-pager --output cat | tail -c 900)
        curl --fail --silent --show-error --retry 3 \
          --form-string "token=$(jq -r .token ${credentials})" \
          --form-string "user=$(jq -r .user ${credentials})" \
          --form-string "sound=${cfg.sound}" \
          --form-string "title=${config.networking.hostName}: $unit failed" \
          --form-string "message=''${log:-no log output}" \
          https://api.pushover.net/1/messages.json
      '';
      serviceConfig.Type = "oneshot";
    };

    homelab.backups.onFailure = [ cfg.unit ];
  };
}
