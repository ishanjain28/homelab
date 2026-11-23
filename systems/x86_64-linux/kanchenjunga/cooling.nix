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
  kernel = config.boot.kernelPackages;
  liquidctl = "${getExe pkgs.liquidctl} --match H150i";

  caseFans = [
    "/sys/devices/platform/it87.2624/hwmon/hwmon[[:print:]]*/pwm3"
    "/sys/devices/platform/it87.2656/hwmon/hwmon[[:print:]]*/pwm1"
    "/sys/devices/platform/it87.2656/hwmon/hwmon[[:print:]]*/pwm3"
  ];

  fancontrol = {
    FCTEMPS = "/sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon[[:print:]]*/temp1_input";
    MINTEMP = "50";
    MAXTEMP = "80";
    MINSTART = "60";
    MINSTOP = "60";
    MINPWM = "60";
    AVERAGE = "6";
  };

  h150iStatus = pkgs.writeShellScript "h150i-status" ''
    XDG_RUNTIME_DIR=/run/telegraf ${liquidctl} --json status | ${getExe pkgs.jq} -r '
      .[].status[]
      | select(.unit == "°C" or .unit == "rpm")
      | (.key | ascii_downcase | sub(" (speed|temperature)$"; "") | gsub(" "; "")) as $feature
      | "sensors,chip=h150i,feature=\($feature) \(if .unit == "rpm" then "fan_input" else "temp_input" end)=\(.value)"
    '
  '';
in
{
  boot.extraModulePackages = [
    (kernel.it87.overrideAttrs {
      postInstall = "mv $out/lib/modules/${kernel.kernel.modDirVersion}/{kernel/drivers/hwmon,updates}";
    })
  ];
  boot.kernelModules = [ "it87" ];
  boot.extraModprobeConfig = "options it87 ignore_resource_conflict=1";

  services.udev.extraRules = ''
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="0c22", GROUP="telegraf", MODE="0660", TAG+="systemd", ENV{SYSTEMD_WANTS}+="h150i.service"
  '';

  systemd.services.h150i = {
    description = "Configure the Corsair H150i pump and fan curve";
    serviceConfig.Type = "oneshot";
    script = ''
      ${liquidctl} initialize --pump-mode balanced
      ${liquidctl} set fan speed 20 25 30 25 34 40 37 60 40 100
    '';
  };

  hardware.fancontrol = enabled // {
    config = concatLines (
      [ "INTERVAL=5" ]
      ++ mapAttrsToList (
        key: value: "${key}=${concatMapStringsSep " " (pwm: "${pwm}=${value}") caseFans}"
      ) fancontrol
    );
  };

  services.telegraf.extraConfig.inputs.exec = [
    {
      commands = [ "${h150iStatus}" ];
      timeout = "10s";
      data_format = "influx";
    }
  ];
}
