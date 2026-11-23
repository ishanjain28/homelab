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

  hwmon = "hwmon/hwmon[[:print:]]*";
  cpuTemp = "/sys/devices/pci0000:00/0000:00:18.3/${hwmon}/temp1_input";
  caseFans = [
    "/sys/devices/platform/it87.2624/${hwmon}/pwm3"
    "/sys/devices/platform/it87.2656/${hwmon}/pwm1"
    "/sys/devices/platform/it87.2656/${hwmon}/pwm3"
  ];
  allFans = value: concatMapStringsSep " " (fan: "${fan}=${toString value}") caseFans;

  h150iStatus = pkgs.writeShellScript "h150i-status" ''
    XDG_RUNTIME_DIR=/run/telegraf ${liquidctl} --json status | ${getExe pkgs.jq} -r '
      .[0].status | map({ (.key): .value }) | add
      | "sensors,chip=h150i,feature=liquid temp_input=\(.["Liquid temperature"])",
        "sensors,chip=h150i,feature=pump fan_input=\(.["Pump speed"])",
        "sensors,chip=h150i,feature=fan1 fan_input=\(.["Fan 1 speed"])",
        "sensors,chip=h150i,feature=fan2 fan_input=\(.["Fan 2 speed"])",
        "sensors,chip=h150i,feature=fan3 fan_input=\(.["Fan 3 speed"])"
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
    config = ''
      INTERVAL=5
      FCTEMPS=${allFans cpuTemp}
      MINTEMP=${allFans 50}
      MAXTEMP=${allFans 80}
      MINSTART=${allFans 60}
      MINSTOP=${allFans 60}
      MINPWM=${allFans 60}
      AVERAGE=${allFans 6}
    '';
  };

  services.telegraf.extraConfig.inputs.exec = [
    {
      commands = [ [ "${h150iStatus}" ] ];
      timeout = "10s";
      data_format = "influx";
    }
  ];
}
