{ lib, namespace }: with lib.${namespace};
{
  ssh = enabled // {
    addRootKeys = true;
    permitRootLogin = false;
  };

  actual-server = enabled // {
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      internet = false;
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30341;
    volumes = [ "actual-server" ];
  };

  pvr-movies-monitor = enabled // {
    networking = {
      vlans = [ 50 ];
      endpoints.app.from = [ "caddy" ];
    };
    runtimeId = 20691;
  };

  huawei-sms = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "huawei_sms";
    };
    networking.vlans = [ 50 ];
    runtimeId = 27777;
  };

  novnc = enabled // {
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      internet = false;
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30397;
    vm = "win11";
  };

  gitea-runner = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 36928;
    giteaURI = "http://gitea:3000";
  };

  mathesar = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "mathesar_django";
    };
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      internet = false;
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30339;
  };

  changedetection = enabled // {
    monitor.name = "Change Detection";
    networking = {
      vlans = [ 50 ];
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30344;
    volumes = [ "changedetection" ];
  };

  openvscode-server = enabled // {
    networking = {
      vlans = [ 50 ];
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30345;
    volumes = [ "openvscode-server" ];
  };
  cups = enabled // {
    networking = {
      vlans = [ 70 ];
      internet = false;
      endpoints = {
        ipp.from = [ "@all_lan" ];
        sane.from = [ "@all_lan" ];
        mdns.from = [
          "@all_lan"
          "@link-local"
        ];
      };
    };
    runtimeId = 30347;
    volumes = [ "cups" ];
  };

  netflector = enabled // {
    networking = {
      vlans = [
        50
        10
        20
        30
        40
        70
      ];
      internet = false;
      endpoints = {
        ssdp.from = [
          "@all_lan"
          "@link-local"
        ];
        wsd.from = [
          "@all_lan"
          "@link-local"
        ];
        mdns.from = [
          "@all_lan"
          "@link-local"
        ];
      };
    };
    runtimeId = 36997;
  };

  ripe-atlas-primary = enabled // {
    networking = {
      vlans = [ 150 ];
      mode = "ipv4";
    };
    runtimeId = 36926;
    volumes = [ "ripe-atlas-primary" ];
  };

  ripe-atlas-lte = enabled // {
    networking = {
      vlans = [ 160 ];
      mode = "ipv4";
    };
    runtimeId = 36927;
    volumes = [ "ripe-atlas-lte" ];
  };

  garmin-sync = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "garmin_data";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30365;
  };

  backrest = enabled // {
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30366;
  };

  bulwark = enabled // {
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      internet = false;
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30393;
  };

  kavita = enabled // {
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      internet = false;
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30395;
    volumes = [ "kavita" ];
  };

  copyparty = enabled // {
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      internet = false;
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30396;
    volumes = [ "copyparty" ];
  };

  obsidian-livesync = enabled // {
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      internet = false;
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30398;
    volumes = [ "obsidian-livesync" ];
  };

  atuin = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "atuin";
    };
    networking = {
      vlans = [ 50 ];
      mode = "ipv6";
      internet = false;
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30394;
  };

  airtrail = enabled // {
    database.instance = "postgresql-home-primary";
    networking = {
      vlans = [ 50 ];
      endpoints.web.from = [ "caddy" ];
    };
    runtimeId = 30399;
    volumes = [ "airtrail" ];
  };
}
