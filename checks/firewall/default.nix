{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;
  unit = import ../../tests/firewall/unit.nix { inherit lib; };
  module =
    (import ../../tests/firewall/module.nix {
      inherit (inputs) nixpkgs;
      system = pkgs.stdenv.hostPlatform.system;
    }).checks;
in
assert module.assertions == [ ] && module.retainOnStop && module.bound && module.ordered;
pkgs.writeText "firewall-unit-results.json" (builtins.toJSON unit)
