{ pkgs, inputs, ... }:
let
  craneLib = inputs.crane.mkLib pkgs;
  src = pkgs.fetchFromGitea {
    domain = "git.ishanjain.me";
    owner = "ishan";
    repo = "huawei-sms-telegram";
    rev = "832cf91b0e709a17001cd9a6e32bb14d740595fb";
    hash = "sha256-KHpCGS7WOm91RLT6dQ4Gz5ev33xg4Xtnp1VA1sMBGck=";
  };
in
craneLib.buildPackage {
  pname = "huawei-sms-telegram";
  version = "0.1.0";
  inherit src;
  strictDeps = true;
}
