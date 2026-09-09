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
  shares = config.${namespace}.shares;
  services = filterAttrs (_name: service: service.enable) config.${namespace}.services;

  shareType = types.submodule {
    options = {
      hostPath = mkOption {
        type = types.str;
        description = "Path mounted unchanged into attached service containers.";
      };

      gid = mkOption {
        type = types.int;
        description = "Shared group ID inside attached service containers.";
      };
    };
  };

  serviceShareIds = service: service.shares or [ ];
  availableShareIds = service: filter (shareId: hasAttr shareId shares) (serviceShareIds service);
  serviceShares = service: map (shareId: shares.${shareId}) (availableShareIds service);
  missingShareRefs = flatten (
    mapAttrsToList (
      serviceName: service:
      map (shareId: "${serviceName}:${shareId}") (
        filter (shareId: !(hasAttr shareId shares)) (serviceShareIds service)
      )
    ) services
  );
  hostGroupName = shareId: "homelab-share-${shareId}";
  shareUnit = shareId: "homelab-share-${shareId}.service";

  mkShareService = shareId: share: {
    "homelab-share-${shareId}" = {
      description = "Prepare homelab share '${shareId}'";
      unitConfig.RequiresMountsFor = [ share.hostPath ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "${pkgs.util-linux}/bin/mountpoint --quiet -- ${escapeShellArg share.hostPath}"
          "${pkgs.coreutils}/bin/chown root:${hostGroupName shareId} ${escapeShellArg share.hostPath}"
          "${pkgs.coreutils}/bin/chmod 2770 ${escapeShellArg share.hostPath}"
        ];
        RemainAfterExit = true;
      };
    };
  };

  mkServiceConfig =
    serviceName: service:
    let
      shareIds = availableShareIds service;
      attachedShares = serviceShares service;
    in
    if shareIds == [ ] then
      {
        containers = { };
        systemd.services = { };
      }
    else
      {
        containers.${serviceName} = {
          bindMounts = mkMerge (
            map (share: {
              ${share.hostPath} = {
                inherit (share) hostPath;
              };
            }) attachedShares
          );

          config = {
            users.groups = mkMerge (
              map (shareId: {
                ${shareId}.gid = mkForce shares.${shareId}.gid;
              }) shareIds
            );
            users.users.${service.runtimeUser.name}.extraGroups = shareIds;
          };
        };

        systemd.services."container@${serviceName}" = {
          requires = map shareUnit shareIds;
          after = map shareUnit shareIds;
        };
      };
in
{
  options.${namespace}.shares =
    mkOpt (types.attrsOf shareType) { }
      "Host filesystems shared by service containers.";

  config = {
    assertions = [
      {
        assertion = missingShareRefs == [ ];
        message = "Enabled services reference unavailable shares on this host: ${concatStringsSep ", " missingShareRefs}";
      }
    ];

    users.groups = mapAttrs' (
      shareId: share:
      nameValuePair (hostGroupName shareId) {
        gid = containerUidOffset + share.gid;
      }
    ) shares;

    systemd.services = mkMerge (
      mapAttrsToList mkShareService shares
      ++ mapAttrsToList (
        serviceName: service: (mkServiceConfig serviceName service).systemd.services
      ) services
    );

    containers = mkMerge (
      mapAttrsToList (serviceName: service: (mkServiceConfig serviceName service).containers) services
    );
  };
}
