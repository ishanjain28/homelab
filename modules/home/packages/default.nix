{ pkgs, ... }: {
  home.packages = with pkgs; [
    curl
    difftastic
    diskus
    fd
    git
    just
    jq
    ripgrep
    scc
    unzip
    whois
    yq
    zip
  ];
}
