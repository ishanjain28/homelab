{
  config,
  lib,
  namespace,
  ...
}:
with lib.${namespace};
{
  ${namespace} = {
    profiles.shell = enabled;
    programs.neovim = enabled;
    services.wallpapers = enabled // {
      directory = "${config.home.homeDirectory}/Downloads/Wallpapers";
    };
  };

  programs.home-manager = enabled;

  # Decrypted at activation by sops-nix with the age key converted from ~/.ssh/id_ed25519.
  sops = {
    age.keyFile = "${config.home.homeDirectory}/Library/Application Support/sops/age/keys.txt";
    secrets.work-gitconfig = {
      sopsFile = lib.snowfall.fs.get-file ".gitconfig.work";
      format = "binary";
    };
  };

  # Corpo re-signs TLS traffic; Nix-built tools only trust this bundle exported from the keychain.
  # The certificate bundle should be present at this location already!
  home.sessionVariables = {
    NIX_SSL_CERT_FILE = "/etc/nix/ca-bundle.pem";
    SSL_CERT_FILE = "/etc/nix/ca-bundle.pem";
    SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
    SSH_AUTH_SOCK = "${config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  };

  programs.git.includes = [ { path = config.sops.secrets.work-gitconfig.path; } ];

  home.stateVersion = "26.05";
}
