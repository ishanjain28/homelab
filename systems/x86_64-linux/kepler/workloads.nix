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
    vlans = [ 50 ];
    runtimeId = 20691;
    ingress.home = {
      domains = [ "pvr.ishanjain.me" ];
      upstreams = [ "10.0.50.36:3000" ];
    };
  };

  huawei-sms-telegram = enabled // {
    vlans = [ 50 ];
    runtimeId = 27777;
  };

  bentopdf = enabled // {
    vlans = [ 50 ];
    runtimeId = 50715;
    ingress.home = {
      domains = [ "pdf.ishanjain.me" ];
      upstreams = [ "10.0.50.22:8080" ];
    };
  };

  lldap = enabled // {
    vlans = [ 50 ];
    runtimeId = 25457;
    ingress.home = {
      domains = [ "ldap.ishanjain.me" ];
      routes = [
        {
          paths = [ "/auth/logout" ];
          handlers = [
            {
              handler = "invoke";
              name = "authelia-logout";
            }
          ];
          upstreams = [ "10.0.50.18:17170" ];
        }
        {
          handlers = [
            {
              handler = "invoke";
              name = "authelia-integration";
            }
          ];
          upstreams = [ "10.0.50.18:17170" ];
        }
      ];
    };
  };

  authelia = enabled // {
    vlans = [ 50 ];
    runtimeId = 20001;
    ingress.home = {
      domains = [ "auth.ishanjain.me" ];
      upstreams = [ "10.0.50.17:9091" ];
    };
  };

  grafana = enabled // {
    vlans = [ 50 ];
    runtimeId = 31918;
    volumes = [ "grafana" ];
    ingress.home = {
      domains = [
        "dash.ishanjain.me"
        "dash.vax.ovh"
      ];
      routes = [
        {
          paths = [ "/logout" ];
          handlers = [
            {
              handler = "invoke";
              name = "authelia-logout";
            }
          ];
          terminal = false;
        }
        {
          matcher.not = [
            {
              path = [
                "/public-dashboards*"
                "/public*"
                "/api/public/dashboards*"
              ];
            }
          ];
          handlers = [
            {
              handler = "invoke";
              name = "authelia-integration";
            }
          ];
          terminal = false;
        }
        {
          upstreams = [ "10.0.50.12:3000" ];
        }
      ];
    };
  };

  mathesar = enabled // {
    vlans = [ 50 ];
    runtimeId = 30339;
    ingress.home = {
      domains = [ "pg.home.ishanjain.me" ];
      upstreams = [ "10.0.50.30:5001" ];
    };
  };

  seerr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30340;
    volumes = [ "seerr" ];
    ingress.home = {
      domains = [ "request.ishanjain.me" ];
      routes = [
        {
          paths = [ "/api/v1/auth/logout" ];
          handlers = [
            {
              handler = "invoke";
              name = "authelia-logout";
            }
          ];
          upstreams = [ "10.0.50.24:5055" ];
          terminal = true;
        }
        {
          handlers = [
            {
              handler = "invoke";
              name = "authelia-integration";
            }
          ];
          upstreams = [ "10.0.50.24:5055" ];
        }
      ];
    };
  };

  actual-server = enabled // {
    vlans = [ 50 ];
    runtimeId = 30341;
    volumes = [ "actual-server" ];
    ingress.home = {
      domains = [ "money.ishanjain.me" ];
      handlers = [
        {
          handler = "invoke";
          name = "authelia-integration";
        }
      ];
      upstreams = [ "10.0.50.19:5006" ];
    };
  };

  changedetection = enabled // {
    vlans = [ 50 ];
    runtimeId = 30344;
    volumes = [ "changedetection" ];
    ingress.home = {
      domains = [ "change.ishanjain.me" ];
      handlers = [
        {
          handler = "invoke";
          name = "authelia-integration";
        }
      ];
      upstreams = [ "10.0.50.27:5000" ];
    };
  };

  openvscode-server = enabled // {
    vlans = [ 50 ];
    runtimeId = 30345;
    volumes = [ "openvscode-server" ];
    ingress.home = {
      domains = [ "editor.ishanjain.me" ];
      handlers = [
        {
          handler = "invoke";
          name = "authelia-integration";
        }
      ];
      upstreams = [ "10.0.50.37:3000" ];
    };
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
    vlans = [ 50 ];
    runtimeId = 30342;
    ingress.home = {
      domains = [ "jt.ishanjain.me" ];
      upstreams = [ "10.0.50.31:3000" ];
    };
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

  cups = enabled // {
    vlans = [ 70 ];
    runtimeId = 30347;
    volumes = [ "cups" ];
    ingress.home = {
      domains = [ "cups.home.ishanjain.me" ];
      handlers = [
        {
          handler = "invoke";
          name = "authelia-integration";
        }
        {
          handler = "headers";
          request.delete = [ "Cookie" ];
        }
      ];
      upstreams = [ "10.0.70.7:631" ];
    };
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

  ripe-atlas-lte = enabled // {
    vlans = [ 160 ];
    runtimeId = 36927;
    volumes = [ "ripe-atlas-lte" ];
  };
}
