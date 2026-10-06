{ lib, namespace }: with lib.${namespace};
{
  ssh = enabled // {
    addRootKeys = true;
    passwordAuth = false;
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
    vlans = [ 50 ];
    runtimeId = 30341;
    volumes = [ "actual-server" ];
  };

  pvr-movies-monitor = enabled // {
    vlans = [ 50 ];
    runtimeId = 20691;
  };

  huawei-sms = enabled // {
    vlans = [ 50 ];
    runtimeId = 27777;
  };

  gitea-runner = enabled // {
    vlans = [ 50 ];
    runtimeId = 36928;
    giteaURI = "http://10.0.50.20:3000";
  };

  mathesar = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "mathesar_django";
    };
    vlans = [ 50 ];
    runtimeId = 30339;
  };

  changedetection = enabled // {
    monitor.name = "Change Detection";
    vlans = [ 50 ];
    runtimeId = 30344;
    volumes = [ "changedetection" ];
  };

  openvscode-server = enabled // {
    vlans = [ 50 ];
    runtimeId = 30345;
    volumes = [ "openvscode-server" ];
  };
  cups = enabled // {
    vlans = [ 70 ];
    runtimeId = 30347;
    volumes = [ "cups" ];
  };

  multicaster = enabled // {
    vlans = [
      10
      20
      30
      40
      70
    ];
    runtimeId = 36925;
  };

  ripe-atlas-primary = enabled // {
    vlans = [ 150 ];
    runtimeId = 36926;
    volumes = [ "ripe-atlas-primary" ];
  };

  ripe-atlas-lte = enabled // {
    vlans = [ 160 ];
    runtimeId = 36927;
    volumes = [ "ripe-atlas-lte" ];
  };

}
