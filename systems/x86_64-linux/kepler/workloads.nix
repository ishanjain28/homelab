{ lib, namespace }:
with lib.${namespace};
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
    vlan = 50;
    runtimeId = 20691;
    monitor = enabled // {
      protocol = "tcp";
    };
  };

  huawei-sms-telegram = enabled // {
    vlan = 50;
    runtimeId = 27777;
    monitor = disabled;
  };

  bentopdf = enabled // {
    vlan = 50;
    runtimeId = 50715;
  };

  lldap = enabled // {
    vlan = 50;
    runtimeId = 25457;
  };

  authelia = enabled // {
    vlan = 50;
    runtimeId = 20001;
  };

  grafana = enabled // {
    vlan = 50;
    runtimeId = 31918;
    volumes = [ "grafana" ];
  };

  mathesar = enabled // {
    vlan = 50;
    runtimeId = 30339;
  };

  seerr = enabled // {
    vlan = 50;
    runtimeId = 30340;
    volumes = [ "seerr" ];
  };

  actual-server = enabled // {
    vlan = 50;
    runtimeId = 30341;
    volumes = [ "actual-server" ];
  };

  changedetection = enabled // {
    vlan = 50;
    runtimeId = 30344;
    volumes = [ "changedetection" ];
  };

  openvscode-server = enabled // {
    vlan = 50;
    runtimeId = 30345;
    volumes = [ "openvscode-server" ];
  };

  vlan10-debug = enabled // {
    vlan = 10;
    runtimeId = 31010;
    logging = disabled;
  };

  vlan20-debug = enabled // {
    vlan = 20;
    runtimeId = 31020;
    logging = disabled;
  };

  vlan30-debug = enabled // {
    vlan = 30;
    runtimeId = 31030;
    logging = disabled;
  };

  vlan40-debug = enabled // {
    vlan = 40;
    runtimeId = 31040;
    logging = disabled;
  };

  vlan50-debug = enabled // {
    vlan = 50;
    runtimeId = 31050;
    logging = disabled;
  };

  vlan99-debug = enabled // {
    vlan = 99;
    runtimeId = 31099;
    logging = disabled;
  };

  vlan140-debug = enabled // {
    vlan = 140;
    runtimeId = 31140;
    logging = disabled;
  };

  vlan150-debug = enabled // {
    vlan = 150;
    runtimeId = 31150;
    logging = disabled;
  };

  vlan160-debug = enabled // {
    vlan = 160;
    runtimeId = 31160;
    logging = disabled;
  };

  tracearr = enabled // {
    vlan = 50;
    runtimeId = 30342;
  };

  loki = enabled // {
    vlan = 50;
    runtimeId = 30343;
    volumes = [ "loki" ];
  };

  alloy-syslog = enabled // {
    vlan = 50;
    runtimeId = 30346;
  };

  gatus = disabled // {
    vlan = 50;
    runtimeId = 36924;
    externalEndpoints = [ ];
  };
}
