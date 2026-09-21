{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  srv = config.${namespace}.services;
  package = pkgs.postgresql_18;
  instances = {
    postgresql-home-primary = "PostgreSQL primary at home";
    postgresql-del-mirror = "PostgreSQL mirror of the Delhi primary";
    postgresql-del-primary = "PostgreSQL primary in Delhi";
  };

  secretsPath = "/run/container-secrets/postgresql.json";

  quoteIdent = name: ''"${name}"'';
  identList = names: concatMapStringsSep ", " quoteIdent names;
  sqlArray = names: "ARRAY[${concatMapStringsSep ", " (name: "'${name}'") names}]::text[]";

  databaseAccess =
    cfg: database:
    let
      readers = unique (cfg.readers ++ database.readers);
      writers = unique (cfg.writers ++ database.writers);
    in
    {
      inherit (database) owner;
      readers = subtractLists writers readers;
      inherit writers;
      allowed = unique ([ database.owner ] ++ readers ++ writers);
    };

  mkClusterSql =
    cfg:
    concatLines (
      concatLists (
        mapAttrsToList (
          user: settings: map (group: "GRANT ${quoteIdent group} TO ${quoteIdent user};") settings.memberOf
        ) cfg.users
      )
      ++ mapAttrsToList (
        name: database:
        let
          access = databaseAccess cfg database;
        in
        ''
          ALTER DATABASE ${quoteIdent name} OWNER TO ${quoteIdent access.owner};
          REVOKE ALL ON DATABASE ${quoteIdent name} FROM PUBLIC;
          DO $$
          DECLARE role_name text;
          BEGIN
            FOR role_name IN
              SELECT rolname FROM pg_roles
              WHERE NOT rolsuper AND rolname NOT LIKE 'pg\_%' AND rolname <> ALL (${sqlArray access.allowed})
            LOOP
              EXECUTE format('REVOKE ALL ON DATABASE %I FROM %I', '${name}', role_name);
            END LOOP;
          END $$;
        ''
        + optionalString (access.readers != [ ]) ''
          GRANT CONNECT, TEMPORARY ON DATABASE ${quoteIdent name} TO ${identList access.readers};
        ''
        + optionalString (access.writers != [ ]) ''
          GRANT CONNECT, TEMPORARY, CREATE ON DATABASE ${quoteIdent name} TO ${identList access.writers};
        ''
      ) cfg.databases
    );

  mkDatabaseSql =
    cfg: _name: database:
    let
      access = databaseAccess cfg database;
      creators = unique ([ access.owner ] ++ access.writers);
      grantAll =
        {
          privileges,
          objects,
          grantees,
        }:
        optionalString (grantees != [ ]) ''
          EXECUTE format('GRANT ${privileges} ON ${objects} %I TO ${identList grantees}', schema_name);
        '';
      defaultPrivileges =
        creator:
        let
          readers = remove creator access.readers;
          writers = remove creator access.writers;
        in
        optionalString (readers != [ ]) ''
          ALTER DEFAULT PRIVILEGES FOR ROLE ${quoteIdent creator} GRANT SELECT ON TABLES TO ${identList readers};
          ALTER DEFAULT PRIVILEGES FOR ROLE ${quoteIdent creator} GRANT SELECT ON SEQUENCES TO ${identList readers};
        ''
        + optionalString (writers != [ ]) ''
          ALTER DEFAULT PRIVILEGES FOR ROLE ${quoteIdent creator} GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${identList writers};
          ALTER DEFAULT PRIVILEGES FOR ROLE ${quoteIdent creator} GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${identList writers};
        '';
    in
    ''
      DO $$
      DECLARE schema_name text;
      DECLARE relation_name text;
      DECLARE role_name text;
      BEGIN
        FOR schema_name IN
          SELECT nspname FROM pg_namespace
          WHERE nspname NOT LIKE 'pg\_%' AND nspname <> 'information_schema'
        LOOP
          IF EXISTS (
            SELECT 1 FROM pg_namespace n JOIN pg_roles r ON r.oid = n.nspowner
            WHERE n.nspname = schema_name
              AND (r.rolsuper OR r.rolname <> ALL (${sqlArray access.allowed}))
              AND r.rolname NOT LIKE 'pg\_%'
              AND NOT EXISTS (
                SELECT 1 FROM pg_depend d
                WHERE d.classid = 'pg_namespace'::regclass AND d.objid = n.oid AND d.deptype = 'e'
              )
          ) THEN
            EXECUTE format('ALTER SCHEMA %I OWNER TO %I', schema_name, '${access.owner}');
          END IF;
          FOR relation_name IN
            SELECT c.relname FROM pg_class c JOIN pg_roles r ON r.oid = c.relowner
            WHERE c.relnamespace = quote_ident(schema_name)::regnamespace
              AND c.relkind IN ('r', 'p', 'S', 'v', 'm', 'f')
              AND (r.rolsuper OR r.rolname <> ALL (${sqlArray access.allowed}))
              AND NOT EXISTS (
                SELECT 1 FROM pg_depend d
                WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e'
              )
          LOOP
            EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', schema_name, relation_name, '${access.owner}');
          END LOOP;
          FOR role_name IN
            SELECT rolname FROM pg_roles
            WHERE NOT rolsuper AND rolname NOT LIKE 'pg\_%' AND rolname <> ALL (${sqlArray access.allowed})
          LOOP
            EXECUTE format('REVOKE ALL ON SCHEMA %I FROM %I', schema_name, role_name);
            EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM %I', schema_name, role_name);
            EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA %I FROM %I', schema_name, role_name);
          END LOOP;
          ${grantAll {
            privileges = "USAGE";
            objects = "SCHEMA";
            grantees = access.readers ++ access.writers;
          }}
          ${grantAll {
            privileges = "SELECT";
            objects = "ALL TABLES IN SCHEMA";
            grantees = access.readers;
          }}
          ${grantAll {
            privileges = "SELECT";
            objects = "ALL SEQUENCES IN SCHEMA";
            grantees = access.readers;
          }}
          ${grantAll {
            privileges = "SELECT, INSERT, UPDATE, DELETE";
            objects = "ALL TABLES IN SCHEMA";
            grantees = access.writers;
          }}
          ${grantAll {
            privileges = "USAGE, SELECT, UPDATE";
            objects = "ALL SEQUENCES IN SCHEMA";
            grantees = access.writers;
          }}
        END LOOP;
      END $$;
    ''
    + concatMapStrings defaultPrivileges creators;

  passwordUsers = name: attrNames (postgresqlInstances.${name}.users or { });

  roleDefaults = {
    superuser = false;
    createdb = false;
    createrole = false;
    login = true;
    replication = false;
    memberOf = [ ];
  };

  databaseDefaults = {
    readers = [ ];
    writers = [ ];
  };

  # Roles, databases and access come from the shared postgresql.json; deployment settings from the option set.
  mkSpec =
    name: cfg:
    let
      instance = postgresqlInstances.${name} or (throw "${postgresqlSecretsFile} has no entry for ${name}");
      passwordRoles = genAttrs (passwordUsers name) (_user: { });
    in
    cfg
    // {
      users = mapAttrs (_role: attrs: roleDefaults // attrs) (passwordRoles // (instance.roles or { }));
      databases = mapAttrs (_database: attrs: databaseDefaults // attrs) (instance.databases or { });
      readers = instance.readers or [ ];
      writers = instance.writers or [ ];
    };

  mkPasswordCommands =
    name:
    concatMapStrings (user: ''
      password="$(jq -r --arg instance ${escapeShellArg name} --arg user ${escapeShellArg user} '.[$instance].users[$user] // ""' ${secretsPath})"
      if [ -n "$password" ]; then
        echo ${escapeShellArg "ALTER ROLE ${quoteIdent user} PASSWORD :'password'"} | psql -X -v ON_ERROR_STOP=1 -v password="$password" -d postgres
      fi
    '') (passwordUsers name);

  mkSetupScript =
    name: cfg:
    let
      clusterSql = pkgs.writeText "${name}-cluster.sql" (mkClusterSql cfg);
      databaseSql = mapAttrs (
        database: settings: pkgs.writeText "${name}-${database}.sql" (mkDatabaseSql cfg database settings)
      ) cfg.databases;
    in
    mkPasswordCommands name
    + ''
      psql -X -v ON_ERROR_STOP=1 -d postgres -f ${clusterSql}
    ''
    + concatStrings (
      mapAttrsToList (database: sql: ''
        psql -X -v ON_ERROR_STOP=1 -d ${escapeShellArg database} -f ${sql}
      '') databaseSql
    );

  mkInstance =
    name: _description:
    let
      cfg = mkSpec name srv.${name};
      referencedRoles = unique (
        cfg.readers
        ++ cfg.writers
        ++ concatLists (
          mapAttrsToList (_name: database: [ database.owner ] ++ database.readers ++ database.writers) cfg.databases
        )
        ++ concatLists (mapAttrsToList (_name: user: user.memberOf) cfg.users)
      );
      undeclaredRoles = filter (role: !(hasAttr role cfg.users)) referencedRoles;
      passwordsWithoutLoginRole = filter (user: !(hasAttr user cfg.users) || !cfg.users.${user}.login) (
        subtractLists [ "replica" ] (passwordUsers name)
      );
    in
    mkIf cfg.enable (mkMerge [
      {
        assertions = [
          {
            assertion = undeclaredRoles == [ ];
            message = "${name}: roles referenced by databases are not declared in users: ${concatStringsSep ", " undeclaredRoles}";
          }
          {
            assertion = passwordsWithoutLoginRole == [ ];
            message = "${name}: ${postgresqlSecretsFile} has passwords for roles that are not declared login users: ${concatStringsSep ", " passwordsWithoutLoginRole}";
          }
        ];
      }
      (mkServiceContainer {
        service = cfg;
        secrets.passwords = {
          file = postgresqlSecretsFile;
          format = "json";
          key = "";
          mountPath = secretsPath;
        };

        inherit (cfg) resources;

        containerConfig = {
          services.postgresql = enabled // {
            inherit package;
            extensions = ps: map (extension: ps.${extension}) cfg.extensions;
            enableTCPIP = true;
            ensureDatabases = attrNames cfg.databases;
            ensureUsers = mapAttrsToList (user: settings: {
              name = user;
              ensureClauses = {
                inherit (settings)
                  superuser
                  createdb
                  createrole
                  login
                  replication
                  ;
              };
            }) cfg.users;
            inherit (cfg) authentication;
            settings = {
              port = cfg.endpoints.postgres.port;
              log_min_messages = "warning";
              log_min_error_statement = "error";
              log_checkpoints = false;
              log_autovacuum_min_duration = -1;
              log_connections = true;
              log_disconnections = true;
            }
            // optionalAttrs (cfg.replicaOf != null) {
              primary_conninfo = "host=${cfg.replicaOf} port=5432 user=replica passfile=/run/postgresql/pgpass";
              primary_slot_name = "homelab";
            }
            // cfg.settings;
          };

          systemd.services.postgresql.serviceConfig.OOMScoreAdjust = -200;
          systemd.services.postgresql.path = [ pkgs.jq ];
          systemd.services.postgresql.preStart = mkIf (cfg.replicaOf != null) (mkBefore ''
            umask 077
            jq -r --arg instance ${escapeShellArg name} '"${cfg.replicaOf}:5432:*:replica:" + .[$instance].users.replica' ${secretsPath} > /run/postgresql/pgpass
          '');
          systemd.services.postgresql-setup = {
            path = [ pkgs.jq ];
            script = mkAfter (mkSetupScript name cfg);
          };
        };
      })
    ]);

in
{
  options.${namespace}.services = mapAttrs (
    name: description:
    mkServiceOptions {
      inherit name description;
      endpoints.postgres.port = 5432;
      monitor = enabled // {
        endpoint = "postgres";
        protocol = "tcp";
      };
    }
    // (with types; {
      runtimeUser = {
        name = mkOpt str "postgres" "User that runs this service inside the container.";
        group = mkOpt str "postgres" "Group that runs this service inside the container.";
      };

      authentication = mkOpt lines "" "pg_hba.conf entries for network clients.";

      replicaOf = mkOpt (nullOr nonEmptyStr) null "Address of the primary this instance streams from.";

      extensions = mkOpt (listOf nonEmptyStr) [ ] "PostgreSQL extension packages installed into this instance.";

      settings = mkOpt (attrsOf (oneOf [
        bool
        float
        int
        str
      ])) { } "postgresql.conf settings pushed to this instance.";

      resources =
        mkOpt
          (attrsOf (oneOf [
            int
            str
          ]))
          {
            CPUQuota = "200%";
            MemoryMax = "2G";
            TasksMax = 512;
          }
          "systemd resource limits for the container.";
    })
  ) instances;

  config = mkMerge (mapAttrsToList mkInstance instances);
}
