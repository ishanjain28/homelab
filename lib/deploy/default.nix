{ inputs }:
let
  inherit (inputs) deploy-rs;
in
{
  mkDeploy =
    { self, fleetRegistry }:
    let
      hosts = self.nixosConfigurations;
      nodes = builtins.deepSeq fleetRegistry.volumes (
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
        }) hosts
      );
    in
    {
      activationTimeout = 900;
      confirmTimeout = 120;
      inherit nodes;
    };
}
