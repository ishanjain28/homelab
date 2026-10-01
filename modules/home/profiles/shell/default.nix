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
  cfg = config.${namespace}.profiles.shell;
in
{
  options.${namespace}.profiles.shell.enable = mkEnableOption "the common fish shell experience";

  config = mkIf cfg.enable {
    home.shellAliases = shellAliases;
    home.sessionVariables = editorVariables;

    programs.fish = enabled // {
      # macOS login shells rebuild PATH from /etc/paths, pushing Apple's /usr/bin (old git)
      # ahead of the Nix profiles. Put them back in front.
      shellInit = mkIf pkgs.stdenv.hostPlatform.isDarwin ''
        fish_add_path --global --move --prepend /nix/var/nix/profiles/default/bin $HOME/.nix-profile/bin /etc/profiles/per-user/$USER/bin
      '';
      interactiveShellInit = fishInteractiveInit;
    };

    programs.bash = enabled // {
      enableCompletion = true;
    };

    # zsh stays usable for scripts and tools that need it, but interactive sessions hand over
    # to fish. Running `zsh` from fish, or setting NO_FISH=1, keeps you in zsh.
    programs.zsh = enabled // {
      enableCompletion = true;
      initContent = mkOrder 200 ''
        if [[ -o interactive && -z "$NO_FISH" && -z "$ZSH_EXECUTION_STRING" ]] \
          && [[ "$(ps -o comm= -p $PPID)" != *fish ]]; then
          exec ${getExe pkgs.fish} ${"$"}{${"$"}{(M)0:#-*}:+--login}
        fi
      '';
    };

    # Single line, and fast: git shows only the branch (no status scan), so large repos stay quick.
    programs.oh-my-posh = enabled // {
      settings = {
        version = 4;
        final_space = true;
        blocks = [
          {
            type = "prompt";
            alignment = "left";
            segments = [
              {
                type = "path";
                style = "plain";
                foreground = "#81A1C1";
                options = {
                  style = "agnoster_short";
                  max_depth = 3;
                  display_root = true;
                };
                template = "{{ .Path }} ";
              }
              {
                type = "git";
                style = "plain";
                foreground = "#6C6C6C";
                options = {
                  fetch_status = false;
                  branch_icon = "";
                };
                template = "{{ .HEAD }} ";
              }
              {
                type = "nix-shell";
                style = "plain";
                foreground = "#88C0D0";
                template = "{{ if ne .Type \"unknown\" }}nix {{ end }}";
              }
              {
                type = "executiontime";
                style = "plain";
                foreground = "#EBCB8B";
                options = {
                  threshold = 5000;
                  style = "round";
                };
                template = "{{ .FormattedMs }} ";
              }
              {
                type = "status";
                style = "plain";
                foreground = "#B48EAD";
                foreground_templates = [ "{{ if gt .Code 0 }}#BF616A{{ end }}" ];
                options.always_enabled = true;
                template = "{{ if gt .Code 0 }}{{ .Code }} {{ end }}❯";
              }
            ];
          }
        ];
      };
    };

    programs.fzf = enabled;

    programs.git = enabled // {
      lfs = enabled;
    };
  };
}
