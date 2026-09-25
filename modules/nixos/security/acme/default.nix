{
  config,
  inputs,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.acme;
  stateDir = "/var/lib/lego";
  deployDir = "${stateDir}/deploy";
  secretPath = config.sops.secrets.acme.path;
  certificateIds = unique (concatMap (consumer: consumer.certificates) (attrValues cfg.consumers));
  consumersOf = id: filterAttrs (_: consumer: elem id consumer.certificates) cfg.consumers;

  mkIssueScript =
    id:
    pkgs.writeShellApplication {
      name = "acme-${id}";
      runtimeInputs = with pkgs; [
        coreutils
        diffutils
        jq
        lego
        systemd
      ];
      text = ''
        secret=${secretPath}
        domains=$(jq -r --arg id ${id} '.certificates[$id] | join(",")' "$secret")
        while IFS= read -r variable; do
          export "''${variable?}"
        done < <(jq -r '.environment | to_entries[] | "\(.key)=\(.value)"' "$secret")

        lego run \
          --path ${stateDir}/${id} \
          --cert.name ${id} \
          --accept-tos \
          --email "$(jq -r '.email' "$secret")" \
          --dns "$(jq -r '.dnsProvider' "$secret")" \
          --domains "$domains" \
          --dns.propagation.wait 60s \
          --force-cert-domains \
          --log.format text

        src=${stateDir}/${id}/certificates
        deploy() {
          local container=$1 owner=$2
          local dst=${deployDir}/$container/${id}
          cmp -s "$src/${id}.crt" "$dst/fullchain.pem" && return
          install -m 0400 -o "$owner" -g "$owner" "$src/${id}.key" "$dst/key.pem"
          install -m 0400 -o "$owner" -g "$owner" "$src/${id}.crt" "$dst/fullchain.pem"
          systemctl --no-block try-restart "container@$container.service"
        }
        ${concatStringsSep "\n" (mapAttrsToList (name: consumer: "deploy ${name} ${toString consumer.uid}") (consumersOf id))}
      '';
    };
in
{
  options.${namespace}.acme = with types; {
    consumers = mkOption {
      type = attrsOf (submodule {
        options = {
          uid = mkOption { type = int; };
          certificates = mkOption { type = listOf nonEmptyStr; };
        };
      });
      default = { };
      internal = true;
    };
  };

  config = mkIf (certificateIds != [ ]) {
    sops.secrets.acme = {
      sopsFile = "${inputs.self}/secrets/acme.json";
      format = "json";
      key = "";
      mode = "0400";
    };

    systemd.tmpfiles.rules = concatLists (
      mapAttrsToList (
        name: consumer:
        map (id: "d ${deployDir}/${name}/${id} 0500 ${toString consumer.uid} ${toString consumer.uid} -") consumer.certificates
      ) cfg.consumers
    );

    systemd.services = listToAttrs (
      map (
        id:
        nameValuePair "acme-${id}" {
          description = "Issue or renew the ${id} certificate";
          after = [
            "network-online.target"
            "nss-lookup.target"
          ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = getExe (mkIssueScript id);
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            StateDirectory = "lego";
            NoNewPrivileges = true;
          };
        }
      ) certificateIds
    );

    systemd.timers = listToAttrs (
      map (
        id:
        nameValuePair "acme-${id}" {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnActiveSec = 0;
            OnCalendar = "daily";
            Persistent = true;
          };
        }
      ) certificateIds
    );
  };
}
