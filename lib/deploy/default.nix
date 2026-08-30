{ inputs }:
let
  inherit (inputs) deploy-rs;
in
{
  mkDeploy =
    { self }:
    let
      hosts = self.nixosConfigurations;
      volumeEntries = builtins.concatLists (
        builtins.attrValues (
          builtins.mapAttrs (
            hostName: machine:
            map (volumeName: { inherit hostName volumeName; }) (
              builtins.attrNames machine.config.system.homelab.volumes
            )
          ) hosts
        )
      );
      volumeHostsByName = builtins.foldl' (
        acc: entry:
        acc
        // {
          ${entry.volumeName} = (acc.${entry.volumeName} or [ ]) ++ [ entry.hostName ];
        }
      ) { } volumeEntries;
      duplicateVolumeNames = builtins.filter (
        volumeName: builtins.length volumeHostsByName.${volumeName} > 1
      ) (builtins.attrNames volumeHostsByName);
      duplicateVolumeMessage = builtins.concatStringsSep ", " (
        map (
          volumeName: "${volumeName}: ${builtins.concatStringsSep ", " volumeHostsByName.${volumeName}}"
        ) duplicateVolumeNames
      );
      nodes =
        if duplicateVolumeNames != [ ] then
          throw "Duplicate homelab volume names across hosts: ${duplicateVolumeMessage}"
        else
          builtins.mapAttrs (_: machine: {
            hostname = machine.config.networking.hostName;
            fastConnection = true;
            remoteBuild = false;
            autoRollback = true;
            magicRollback = true;
            profiles.system = {
              user = "root";
              sshUser = "ishan";
              path = deploy-rs.lib.${machine.pkgs.stdenv.hostPlatform.system}.activate.nixos machine;
            };
          }) hosts;
    in
    {
      inherit nodes;
    };
}
