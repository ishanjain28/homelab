{ inputs, stdenv, ... }:
(inputs.deploy-rs.lib.${stdenv.hostPlatform.system}.deployChecks inputs.self.deploy).deploy-schema
