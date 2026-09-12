{ pkgs, ... }:
let
  pname = "caddy";
  version = "2.11.4";
  src = ./.;
in
pkgs.buildGoModule {
  inherit pname version src;

  vendorHash = "sha256-TdPMxefSzVVUSVpgqJ0mmoWolaIQQeBOJb3qQxdqDcY=";

  postPatch = ''
    go mod edit -require=github.com/caddyserver/caddy/v2@v${version}
  '';

  meta = {
    description = "Caddy Web Server";
    homepage = "https://github.com/caddyserver/caddy";
    mainProgram = pname;
    platforms = pkgs.lib.platforms.linux;
  };
}
