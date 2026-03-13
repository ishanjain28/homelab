# Homelab

### Bootstrapping nodes from Minimal Nix ISO

1. Set password for `nixos` and `root` users after logging in.
2. Use `nixos-anywhere` to configure the node.

    nix run github:nix-community/nixos-anywhere -- --flake .#kepler root@<address>



## TODO

1. generate caddy config from services config.
2. Route all logs using rsyslog to one place.
3. Maybe generate dnsconfig.js from services data.
4. Test creating containers in a vlan.
5. create vms
6. Implement migratable mounts that are copied from one node to the other when a service is moved. mounts can be identified using a fixed id for non-epheraml data.
7. implement disk partitioning using lvm and implement moving using built in lvm features.
