{ lib, namespace }: with lib.${namespace};
{
  postgresql-home-primary = enabled // {
    monitor.name = "PostgreSQL Primary";
    networking.vlans = [ 50 ];
    runtimeId = 36932;
    volumes = [ "postgresql-home-primary" ];
    resources = {
      CPUQuota = "400%";
      MemoryMax = "4G";
      TasksMax = 1024;
    };
    extensions = [ "timescaledb" ];
    authentication = ''
      host all all 10.0.50.0/24 scram-sha-256
      host all all 2a0a:6040:4004:50::/64 scram-sha-256
      host all ishan 10.0.10.0/24 scram-sha-256
      host all ishan 2a0a:6040:4004:10::/64 scram-sha-256
    '';
    settings = {
      max_connections = 100;
      shared_buffers = "1GB";
      effective_cache_size = "3GB";
      work_mem = "8MB";
      maintenance_work_mem = "512MB";
      dynamic_shared_memory_type = "posix";
      effective_io_concurrency = 256;
      max_worker_processes = 24;
      max_parallel_workers_per_gather = 2;
      max_parallel_workers = 4;
      wal_buffers = "16MB";
      wal_level = "replica";
      max_wal_senders = 10;
      wal_keep_size = "128MB";
      checkpoint_completion_target = 0.9;
      max_wal_size = "1GB";
      min_wal_size = "512MB";
      random_page_cost = 1.1;
      default_statistics_target = 100;
      max_locks_per_transaction = 2048;
      autovacuum_worker_slots = 8;
      autovacuum_max_workers = 4;
      autovacuum_naptime = 10;
      default_toast_compression = "lz4";
      datestyle = "iso, mdy";
      timezone = "Asia/Kolkata";
      log_timezone = "Asia/Kolkata";
      default_text_search_config = "pg_catalog.english";
      shared_preload_libraries = "timescaledb";
      "timescaledb.max_background_workers" = 12;
    };
  };

  postgresql-del-mirror = enabled // {
    monitor.name = "PostgreSQL Secondary";
    networking.vlans = [ 50 ];
    runtimeId = 36933;
    volumes = [ "postgresql-del-mirror" ];
    resources = {
      CPUQuota = "200%";
      MemoryMax = "2G";
      TasksMax = 512;
    };
    replicaOf = "10.1.1.3";
    authentication = ''
      host all all 10.0.50.0/24 scram-sha-256
      host all ishan 10.0.10.0/24 scram-sha-256
    '';
    settings = {
      max_connections = 100;
      shared_buffers = "512MB";
      dynamic_shared_memory_type = "posix";
      wal_level = "replica";
      wal_compression = true;
      max_wal_size = "1GB";
      min_wal_size = "80MB";
      datestyle = "iso, mdy";
      timezone = "Asia/Kolkata";
      log_timezone = "Asia/Kolkata";
      default_text_search_config = "pg_catalog.english";
    };
  };

  karakeep = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30348;
    volumes = [
      "karakeep"
      "karakeep-meilisearch"
    ];
  };

  bentopdf = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 50715;
  };

  tracearr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "tracearr";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30342;
  };

  omada = enabled // {
    monitor.name = "Omada Controller";
    networking.vlans = [ 99 ];
    runtimeId = 30349;
    volumes = [ "omada" ];
  };

  prowlarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "prowlarr-main";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30350;
  };

  radarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "radarrmain";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30354;
    shares = [ "wd-4tb" ];
  };

  sonarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "sonarrmain";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30355;
    shares = [ "wd-4tb" ];
  };

  bazarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "bazarr";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30356;
    volumes = [ "bazarr" ];
    shares = [ "wd-4tb" ];
  };

  lidarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "lidarrmain";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30358;
    shares = [ "music" ];
  };

  unpackerr = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30359;
    shares = [ "wd-4tb" ];
  };

  qbittorrent = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30361;
    volumes = [ "qbittorrent" ];
    shares = [ "wd-4tb" ];
  };

  jellyfin = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 30360;
    volumes = [ "jellyfin" ];
    shares = [
      "wd-4tb"
      "music"
    ];
    devices = [ "render" ];
  };

  gitea = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "gitea";
    };
    networking.vlans = [ 50 ];
    runtimeId = 36930;
    volumes = [ "gitea" ];
  };

  victoriametrics = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 36929;
    volumes = [ "victoriametrics" ];
  };

  victorialogs = enabled // {
    networking.vlans = [
      50
      99
    ];
    runtimeId = 36935;
    volumes = [ "victorialogs" ];
  };

  grafana = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "grafana";
    };
    networking.vlans = [ 50 ];
    runtimeId = 31918;
    volumes = [ "grafana" ];
  };

  paperless = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "paperless";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30387;
    shares = [ "paperless" ];
    volumes = [ "paperless" ];
  };

  samba = enabled // {
    monitor.name = "NAS";
    networking.vlans = [ 50 ];
    runtimeId = 30363;
    shares = [
      "ishan"
      "yogesh"
      "suman"
      "deshna"
      "music"
      "wd-4tb"
      "shared"
      "emeraldbackups"
      "paperless"
    ];
  };

  caddy = enabled // {
    monitor.name = "Ingress Proxy IPv4";
    networking.vlans = [
      50
      140
    ];
    runtimeId = 30352;
    configFile = "secrets/caddy/home.json";
  };

  adguardhome = enabled // {
    monitor = {
      name = "Home DNS";
      group = "Homelab";
      endpoint = "tls";
      protocol = "tls";
      client.insecure = true;
      conditions = [
        "[CONNECTED] == true"
        "[CERTIFICATE_EXPIRATION] > 96h"
      ];
    };
    networking = {
      vlans = [ 99 ];
      endpoints = {
        dns = {
          port = 53;
          transport = "tcp-and-udp";
        };
        tls = {
          port = 853;
          transport = "tcp-and-udp";
        };
        https.port = 443;
        web = {
          port = 80;
          expose = true;
        };
      };
    };
    runtimeId = 30373;
    configFile = "secrets/adguardhome/home.yaml";
    certificates = [ "adguard-home" ];
  };

  asterisk = enabled // {
    networking.vlans = [ 140 ];
    runtimeId = 30362;
    logging = disabled;
  };

  lldap = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "ldap";
    };
    networking.vlans = [ 50 ];
    runtimeId = 25457;
  };

  authelia = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "authelia";
    };
    networking.vlans = [ 50 ];
    runtimeId = 20001;
  };

  stalwart = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "stalwart";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30364;
    volumes = [ "stalwart" ];
    certificates = [ "mail-home" ];
  };

  windmill = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "windmill";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30353;
  };

  gatus = enabled // {
    networking.vlans = [
      50
      10
      99
      70
      140
    ];
    runtimeId = 36924;
    database = {
      instance = "postgresql-home-primary";
      name = "gatus";
    };
    envFile = "secrets/gatus/home.env";
    endpointsFile = "secrets/gatus/home.yml";
  };

  vlan10-debug = enabled // {
    networking.vlans = [ 10 ];
    runtimeId = 31010;
  };

  vlan20-debug = enabled // {
    networking.vlans = [ 20 ];
    runtimeId = 31020;
  };

  vlan30-debug = enabled // {
    networking.vlans = [ 30 ];
    runtimeId = 31030;
  };

  vlan40-debug = enabled // {
    networking.vlans = [ 40 ];
    runtimeId = 31040;
  };

  vlan50-debug = enabled // {
    networking.vlans = [ 50 ];
    runtimeId = 31050;
  };

  vlan99-debug = enabled // {
    networking.vlans = [ 99 ];
    runtimeId = 31099;
  };

  vlan140-debug = enabled // {
    networking.vlans = [ 140 ];
    runtimeId = 31140;
  };

  vlan150-debug = enabled // {
    networking.vlans = [ 150 ];
    runtimeId = 31150;
  };

  vlan160-debug = enabled // {
    networking.vlans = [ 160 ];
    runtimeId = 31160;
  };

  seerr = enabled // {
    monitor.name = "Jellyseerr";
    database = {
      instance = "postgresql-home-primary";
      name = "jellyseerr";
    };
    networking.vlans = [ 50 ];
    runtimeId = 30340;
  };

  alloy-syslog = enabled // {
    monitor.name = "Syslog";
    networking.vlans = [
      50
      99
    ];
    runtimeId = 30346;
  };

  telegraf-snmp = enabled // {
    networking.vlans = [
      50
      99
    ];
    runtimeId = 36931;
  };

}
