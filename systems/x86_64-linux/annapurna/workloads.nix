{ lib, namespace }: with lib.${namespace};
{
  postgresql-home-primary = enabled // {
    vlans = [ 50 ];
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
      host all ishan 10.0.10.0/24 scram-sha-256
    '';
    settings = {
      max_connections = 100;
      shared_buffers = "1GB";
      effective_cache_size = "3GB";
      work_mem = "8MB";
      maintenance_work_mem = "512MB";
      dynamic_shared_memory_type = "posix";
      effective_io_concurrency = 256;
      max_worker_processes = 16;
      max_parallel_workers_per_gather = 2;
      max_parallel_workers = 4;
      wal_buffers = "16MB";
      wal_level = "replica";
      max_wal_senders = 10;
      wal_keep_size = "512MB";
      checkpoint_completion_target = 0.9;
      max_wal_size = "1GB";
      min_wal_size = "512MB";
      random_page_cost = 1.1;
      default_statistics_target = 100;
      max_locks_per_transaction = 512;
      autovacuum_worker_slots = 8;
      autovacuum_max_workers = 4;
      autovacuum_naptime = 10;
      default_toast_compression = "lz4";
      datestyle = "iso, mdy";
      timezone = "Asia/Kolkata";
      log_timezone = "Asia/Kolkata";
      default_text_search_config = "pg_catalog.english";
      shared_preload_libraries = "timescaledb";
      "timescaledb.max_background_workers" = 8;
    };
  };

  postgresql-del-mirror = enabled // {
    vlans = [ 50 ];
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
    vlans = [ 50 ];
    runtimeId = 30348;
    volumes = [
      "karakeep"
      "karakeep-meilisearch"
    ];
  };

  omada = enabled // {
    vlans = [ 99 ];
    runtimeId = 30349;
    volumes = [ "omada" ];
  };

  prowlarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "prowlarr-main";
    };
    vlans = [ 50 ];
    runtimeId = 30350;
  };

  radarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "radarrmain";
    };
    vlans = [ 50 ];
    runtimeId = 30354;
    shares = [ "wd-4tb" ];
  };

  sonarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "sonarrmain";
    };
    vlans = [ 50 ];
    runtimeId = 30355;
    shares = [ "wd-4tb" ];
  };

  bazarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "bazarr";
    };
    vlans = [ 50 ];
    runtimeId = 30356;
    volumes = [ "bazarr" ];
    shares = [ "wd-4tb" ];
  };

  lidarr = enabled // {
    database = {
      instance = "postgresql-home-primary";
      name = "lidarrmain";
    };
    vlans = [ 50 ];
    runtimeId = 30358;
    shares = [ "music" ];
  };

  unpackerr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30359;
    shares = [ "wd-4tb" ];
  };

  qbittorrent = enabled // {
    vlans = [ 50 ];
    runtimeId = 30361;
    volumes = [ "qbittorrent" ];
    shares = [ "wd-4tb" ];
  };

  jellyfin = enabled // {
    vlans = [ 50 ];
    runtimeId = 30360;
    volumes = [ "jellyfin" ];
    shares = [
      "wd-4tb"
      "music"
    ];
    devices = [ "render" ];
  };

  nitter = enabled // {
    vlans = [ 50 ];
    runtimeId = 30351;
  };

  samba = enabled // {
    vlans = [ 50 ];
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
    ];
  };

  caddy = enabled // {
    vlans = [
      50
      140
    ];
    runtimeId = 30352;
    configFile = "secrets/caddy/home.json";
  };
}
