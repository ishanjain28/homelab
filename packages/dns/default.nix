{ inputs, pkgs, ... }:
let
  config = ../../tools/dns;
  secrets = ../../secrets/dns;
  direct = pkgs.writeText "dns-direct.json" (builtins.toJSON inputs.self.dnsDirect);
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

    creds=()
    if [ "$command" = preview ] || [ "$command" = push ]; then
      creds=(--creds "!sops decrypt ${secrets}/creds.json --output-type json")
    fi

    cd "$(mktemp -d)"
    trap 'rm -rf "$PWD"' EXIT
    sops decrypt ${secrets}/records.json > records.json
    cp ${direct} direct.json

    dnscontrol "$command" --config ${config}/dnsconfig.js "''${creds[@]}" \
      -v dns="$PWD/records.json" -v direct="$PWD/direct.json" "$@"
  '';
}
