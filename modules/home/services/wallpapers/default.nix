{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.services.wallpapers;

  # Google offers no API for reading shared albums, so this scrapes the public album page.
  sync = pkgs.writeShellApplication {
    name = "wallpapers-sync";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gawk
      gnugrep
    ];
    text = ''
      # Activation doesn't inherit session variables (e.g. SSL_CERT_FILE behind a TLS proxy).
      set +u
      unset __HM_SESS_VARS_SOURCED
      # shellcheck source=/dev/null
      . ${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh
      set -u

      dir=${escapeShellArg cfg.directory}
      mkdir -p "$dir"
      page="$(curl -fsSL ${escapeShellArg cfg.album})"
      # Each photo is listed as ["<url>",<width>,<height>; keep landscape ones only.
      photos="$(grep -oE '\["https://lh3\.googleusercontent\.com/pw/[A-Za-z0-9_-]+",[0-9]+,[0-9]+' <<<"$page" \
        | tr -d '["' | awk -F, '$2 > $3' | sort -u)"
      [[ -n "$photos" ]] || { echo "no landscape photos found in album" >&2; exit 1; }

      keep=()
      while IFS=, read -r url width height; do
        src="$url=w$width-h$height"
        name="$(sha256sum <<<"$src" | cut -c1-16).jpg"
        keep+=("$name")
        [[ -e "$dir/$name" ]] && continue
        curl -fsSL -o "$dir/.$name" "$src" && mv "$dir/.$name" "$dir/$name"
      done <<<"$photos"

      for file in "$dir"/*.jpg; do
        [[ -e "$file" ]] || continue
        [[ " ''${keep[*]} " == *" $(basename "$file") "* ]] || rm -f "$file"
      done
    '';
  };
in
{
  options.${namespace}.services.wallpapers = {
    enable = mkEnableOption "syncing wallpapers from a public Google Photos album";
    album = mkOpt types.str "https://photos.app.goo.gl/Cs2szWqUphnaTW8N9" "Public Google Photos album link.";
    directory = mkOption {
      type = types.str;
      description = "Where to sync the album's photos. Files not in the album are deleted from it.";
    };
  };

  config = mkIf cfg.enable {
    home.activation.wallpapers = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      run ${getExe sync} || echo "wallpapers: sync failed, keeping existing photos" >&2
    '';
  };
}
