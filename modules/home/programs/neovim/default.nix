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
  cfg = config.${namespace}.programs.neovim;
in
{
  options.${namespace}.programs.neovim.enable = mkEnableOption "neovim as the default editor";

  config = mkIf cfg.enable {
    programs.neovim = enabled // {
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      withPython3 = false;
      withRuby = false;

      initLua = builtins.readFile ./init.lua;

      plugins = with pkgs.vimPlugins; [
        # Completion
        nvim-cmp
        cmp-nvim-lsp
        cmp-nvim-lua
        cmp-nvim-lsp-signature-help
        cmp-vsnip
        cmp-path
        cmp-buffer
        cmp-calc
        vim-vsnip

        # General enhancements
        bclose-vim
        vim-floaterm

        # LSP
        nvim-lspconfig

        # Language support
        rustaceanvim
        pgsql-vim
        nvim-treesitter.withAllGrammars

        # Fuzzy finder
        fzf-vim

        # UI
        lightline-vim
        modus-themes-nvim
      ];

      # Language servers. clangd is left to the project's toolchain (Chromium, devshells).
      extraPackages = with pkgs; [
        gopls
        lua-language-server
        nixd
        rust-analyzer
        typescript-language-server
      ];
    };

    xdg.configFile."nvim/lua/functions.lua".source = ./lua/functions.lua;
  };
}
