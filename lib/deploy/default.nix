{ inputs }:
let
  inherit (inputs) deploy-rs;
in
{
  mkDeploy =
    { self }:
    let
      hosts = self.nixosConfigurations or { };
      nodes = builtins.mapAttrs (_: machine: {
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
