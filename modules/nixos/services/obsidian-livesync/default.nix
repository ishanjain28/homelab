{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  cfg = srv.obsidian-livesync;
  adminPath = "/run/container-secrets/obsidian-livesync-admin.ini";
in
{
  options.${namespace}.services.obsidian-livesync = mkServiceOptions {
    name = "obsidian-livesync";
    description = "CouchDB for Obsidian Self-hosted LiveSync";
    endpoints.web.port = 5984;
    monitor = enabled // {
      endpoint = "web";
      protocol = "tcp";
    };
  };

  config = mkIf cfg.enable (mkServiceContainer {
    service = cfg;
    serviceProfiles.couchdb = "jit";
    secrets.admin = {
      file = "secrets/obsidian-livesync/admin.conf";
      format = "binary";
      mountPath = adminPath;
    };
    resources = {
      CPUQuota = "200%";
      MemoryMax = "1G";
      TasksMax = 512;
    };
    containerConfig = {
      services.couchdb = enabled // {
        user = cfg.runtimeUser.name;
        group = cfg.runtimeUser.group;
        bindAddress = "::";
        port = cfg.networking.endpoints.web.port;
        extraConfigFiles = [ adminPath ];
        extraConfig = {
          couchdb = {
            single_node = true;
            max_document_size = 50000000;
          };
          cluster.n = 1;
          chttpd = {
            require_valid_user = true;
            enable_cors = true;
            max_http_request_size = 4294967296;
          };
          chttpd_auth.require_valid_user = true;
          httpd = {
            WWW-Authenticate = ''Basic realm="couchdb"'';
            enable_cors = true;
          };
          cors = {
            credentials = true;
            origins = "app://obsidian.md,capacitor://localhost,http://localhost";
          };
          log.writer = "stderr";
        };
      };
    };
  });
}
