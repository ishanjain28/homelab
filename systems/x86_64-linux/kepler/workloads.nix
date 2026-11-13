{ lib, namespace }: with lib.${namespace};
{
  ssh = enabled // {
    addRootKeys = true;
    permitRootLogin = false;
  };

  tailscale = {
    advertiseRoutes = [
      "10.0.10.0/24"
      "10.0.20.0/24"
      "10.0.30.0/24"
      "10.0.40.0/24"
      "10.0.50.0/24"
      "10.0.60.0/24"
      "10.0.70.0/24"
      "10.0.99.0/24"
      "10.0.140.0/24"
      "10.0.150.0/24"
      "10.0.160.0/24"
    ];
  };

  actual-server = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30341;
    volumes = [ "actual-server" ];
  };

  pvr-movies-monitor = enabled // {
    networking.vlans = [ 50 ];
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

  gitea-runner = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 36928;
    giteaURI = "https://git.ishanjain.me";
  };

  mathesar = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "mathesar_django";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30339;
  };

  changedetection = enabled // {
    monitor.name = "Change Detection";
    networking.vlans = [ 50 ];
    runtimeId = 30344;
    volumes = [ "changedetection" ];
  };

  openvscode-server = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30345;
    volumes = [ "openvscode-server" ];
  };
  cups = enabled // {
    networking.vlans = [ 70 ];
    runtimeId = 30347;
    volumes = [ "cups" ];
  };

  multicaster = enabled // {
    networking.vlans = [
      10
      20
      30
      40
      70
    ];
    runtimeId = 36925;
  };

  netflector = enabled // {
    networking.vlans = [
      50
      10
      20
      30
      40
    ];
    runtimeId = 36997;
  };

  ripe-atlas-primary = enabled // {
    networking.vlans = [ 150 ];
    runtimeId = 36926;
    volumes = [ "ripe-atlas-primary" ];
  };

  ripe-atlas-lte = enabled // {
    networking.vlans = [ 160 ];
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
    networking.vlans = [ 50 ];
    runtimeId = 30366;
  };

  bulwark = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30393;
  };

  kavita = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30395;
    volumes = [ "kavita" ];
  };

  copyparty = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30396;
    volumes = [ "copyparty" ];
  };

  atuin = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "atuin";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30394;
  };
}
