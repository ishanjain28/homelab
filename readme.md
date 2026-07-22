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
8. generate a better minimal iso with the right ssh access.
9. Add deployment order dependency if possible.
10. Grow and shrink LVS based on updated values. Require user action if the LVS was shrunk!
11. service.networking similar to hardware.networking ?
12. modify systemd-resolved to disable fallback servers. Maybe disable stub resolver.
13. run ssh in every service container for direct access.
14. host side vbridge interfaces for containers should have minimal vlan access. A service in untagged vlan 10 should be attached to a veth interface on host that also only allows vlan10.
