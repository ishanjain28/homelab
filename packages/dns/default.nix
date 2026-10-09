{ pkgs, ... }:
let
  config = ../../tools/dns;
  secrets = ../../secrets/dns;
in
pkgs.writeShellApplication {
  name = "dns";
  runtimeInputs = with pkgs; [
    dnscontrol
    sops
  ];
  text = ''
    command="''${1:-preview}"
    shift || true

    creds=""
    if [ "$command" = preview ] || [ "$command" = push ]; then
      creds="--creds '!sops decrypt ${secrets}/creds.json --output-type json'"
    fi

    sops exec-file --no-fifo --filename records.json ${secrets}/records.json \
      "dnscontrol $command --config ${config}/dnsconfig.js $creds -v dns={} $*"
  '';
}
