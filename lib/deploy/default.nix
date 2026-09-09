{ inputs }:
let
  inherit (inputs) deploy-rs;
  registryLib = import ../registry/default.nix { lib = inputs.nixpkgs.lib; };
in
{
  mkDeploy =
    { self }:
    let
      hosts = self.nixosConfigurations;
      hostRegistries = builtins.mapAttrs (
        _hostName: machine: machine.config.system.homelab.registry
      ) hosts;
      fleetRegistry = registryLib.mkFleetRegistry hostRegistries;
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
      inherit nodes;
    };
}
