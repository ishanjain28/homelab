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

  pvr-movies-monitor = enabled // {
    vlans = [ 50 ];
    runtimeId = 20691;
  };

  huawei-sms = enabled // {
    vlans = [ 50 ];
    runtimeId = 27777;
  };

  gitea = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "gitea";
    };
    vlans = [ 50 ];
    runtimeId = 36930;
    volumes = [ "gitea" ];
  };

  gitea-runner = enabled // {
    vlans = [ 50 ];
    runtimeId = 36928;
    giteaURI = "http://10.0.50.20:3000";
  };

  asterisk = enabled // {
    vlans = [ 140 ];
    runtimeId = 30362;
    logging = disabled;
  };

  # TODO: windmill pkg in nixpkgs is very old. need to update that!
  windmill = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "windmill";
    };
    vlans = [ 50 ];
    runtimeId = 30353;
  };

  bentopdf = enabled // {
    vlans = [ 50 ];
    runtimeId = 50715;
  };

  lldap = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "ldap";
    };
    vlans = [ 50 ];
    runtimeId = 25457;
  };

  authelia = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "authelia";
    };
    vlans = [ 50 ];
    runtimeId = 20001;
  };

  grafana = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "grafana";
    };
    vlans = [ 50 ];
    runtimeId = 31918;
    volumes = [ "grafana" ];
  };

  mathesar = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "mathesar_django";
    };
    vlans = [ 50 ];
    runtimeId = 30339;
  };

  seerr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "jellyseerr";
    };
    vlans = [ 50 ];
    runtimeId = 30340;
    volumes = [ "seerr" ];
  };

  actual-server = enabled // {
    vlans = [ 50 ];
    runtimeId = 30341;
    volumes = [ "actual-server" ];
  };

  changedetection = enabled // {
    vlans = [ 50 ];
    runtimeId = 30344;
    volumes = [ "changedetection" ];
  };

  openvscode-server = enabled // {
    vlans = [ 50 ];
    runtimeId = 30345;
    volumes = [ "openvscode-server" ];
  };

  vlan10-debug = enabled // {
    vlans = [ 10 ];
    runtimeId = 31010;
  };

  vlan20-debug = enabled // {
    vlans = [ 20 ];
    runtimeId = 31020;
  };

  vlan30-debug = enabled // {
    vlans = [ 30 ];
    runtimeId = 31030;
  };

  vlan40-debug = enabled // {
    vlans = [ 40 ];
    runtimeId = 31040;
  };

  vlan50-debug = enabled // {
    vlans = [ 50 ];
    runtimeId = 31050;
  };

  vlan99-debug = enabled // {
    vlans = [ 99 ];
    runtimeId = 31099;
  };

  vlan140-debug = enabled // {
    vlans = [ 140 ];
    runtimeId = 31140;
  };

  vlan150-debug = enabled // {
    vlans = [ 150 ];
    runtimeId = 31150;
  };

  vlan160-debug = enabled // {
    vlans = [ 160 ];
    runtimeId = 31160;
  };

  tracearr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "tracearr";
    };
    vlans = [ 50 ];
    runtimeId = 30342;
  };

  loki = enabled // {
    vlans = [
      50
      70
      99
    ];
    runtimeId = 30343;
    volumes = [ "loki" ];
  };

  alloy-syslog = enabled // {
    vlans = [ 50 ];
    runtimeId = 30346;
  };

  victoriametrics = enabled // {
    vlans = [ 50 ];
    runtimeId = 36929;
    volumes = [ "victoriametrics" ];
  };

  cups = enabled // {
    vlans = [ 70 ];
    runtimeId = 30347;
    volumes = [ "cups" ];
  };

  gatus = disabled // {
    vlans = [ 50 ];
    runtimeId = 36924;
    externalEndpoints = [ ];
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

  telegraf-snmp = enabled // {
    vlans = [
      50
      99
    ];
    runtimeId = 36931;
  };

  ripe-atlas-lte = enabled // {
    vlans = [ 160 ];
    runtimeId = 36927;
    volumes = [ "ripe-atlas-lte" ];
  };
}
