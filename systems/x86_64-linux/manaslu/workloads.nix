{ lib, namespace }: with lib.${namespace};
{
  postgresql-del-primary = enabled // {
    monitor.group = "DEL";
    monitor.name = "PostgreSQL Primary";
    volumes = [ "postgresql-del-primary" ];
    hostNetwork = true;
    runtimeId = 36934;
    authentication = ''
      host all all 127.0.0.1/32 scram-sha-256
      host replication replica 10.1.1.0/24 scram-sha-256
    '';
    settings = {
      listen_addresses = "127.0.0.1,10.1.1.3";
      shared_buffers = "128MB";
      wal_level = "replica";
      max_wal_senders = 10;
      timezone = "Asia/Kolkata";
    };
  };
  caddy = enabled // {
    hostNetwork = true;
    runtimeId = 30352;
    configFile = "secrets/caddy/delhi.json";
    shares = [ "dl" ];
    endpoints = {
      http.port = 10080;
      https = {
        port = 10443;
        transport = "tcp-and-udp";
      };
      admin = {
        port = 2019;
        expose = false;
      };
    };
    monitor = {
      endpoint = "http";
      group = "DEL";
      name = "Public Proxy IPv4";
    };
  };
  adguardhome = enabled // {
    monitor.group = "DEL";
    hostNetwork = true;
    runtimeId = 30373;
    configFile = "secrets/adguardhome/delhi.yml";
    certificates = [ "adguard-home" ];
    endpoints = {
      dns = {
        port = 5353;
        transport = "tcp-and-udp";
      };
      tls = {
        port = 8853;
        transport = "tcp-and-udp";
      };
      https.port = 8443;
      web = {
        port = 1030;
        expose = false;
      };
    };
  };
  gatus = enabled // {
    hostNetwork = true;
    runtimeId = 36924;
  };
  vaultwarden = enabled // {
    monitor.group = "DEL";
    volumes = [ "vaultwarden" ];
    hostNetwork = true;
    runtimeId = 30390;
  };
  freshrss = enabled // {
    monitor.group = "DEL";
    volumes = [ "freshrss" ];
    hostNetwork = true;
    runtimeId = 30391;
    database = {
      instance = "postgresql-del-primary";
      name = "freshrss";
    };
    baseUrl = "https://rss.ishanjain.me";
  };
  bird = enabled // {
    config = builtins.readFile ./bird.conf;
  };
  znc = enabled // {
    monitor.group = "DEL";
    volumes = [ "znc" ];
    runtimeId = 30392;
    hostNetwork = true;
  };
  wireguard = enabled // {
    interfaces = {
      wg-home-vpn = enabled // {
        configFile = "secrets/wg-home-vpn.conf";
        listenPort = 51820;
      };
      wg-ipv6 = enabled // {
        configFile = "secrets/wg-ipv6.conf";
        listenPort = 51377;
      };
    };
  };
}
