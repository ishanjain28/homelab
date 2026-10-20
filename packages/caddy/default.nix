{ pkgs, ... }:
let
  pname = "caddy";
  version = "2.11.7";
  src = ./.;
in
pkgs.buildGoModule {
  inherit pname version src;

  vendorHash = "sha256-Wx8wT1KdlL1kQSlw+tXnhYhIcI+gINYAYcQnEeeh/vs=";

  postPatch = ''
    go mod edit -require=github.com/caddyserver/caddy/v2@v${version}
  '';

  overrideModAttrs = _: { preBuild = "go mod tidy"; };

  modPostBuild = "cp go.mod go.sum vendor/";

  preBuild = "cp vendor/go.mod vendor/go.sum .";

  meta = {
    description = "Caddy Web Server";
    homepage = "https://github.com/caddyserver/caddy";
    mainProgram = pname;
    platforms = pkgs.lib.platforms.linux;
  };
}
