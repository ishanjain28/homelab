# Homelab



## Bootstrapping nodes from Minimal Nix ISO

1. Set password for `nixos` and `root` users after logging in.
2. Use `nixos-anywhere` to configure the node.

    nix run github:nix-community/nixos-anywhere -- --flake .#kepler root@<address>
