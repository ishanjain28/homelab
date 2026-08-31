# Homelab

### Bootstrapping nodes from Minimal Nix ISO

1. Set password for `nixos` and `root` users after logging in.
2. Use `nixos-anywhere` to configure the node.

    nix run github:nix-community/nixos-anywhere -- --flake .#kepler root@<address>



## TODO

[] generate caddy config from services config.
[x]. Route all logs using rsyslog to one place.
[]. Maybe generate dnsconfig.js from services data.
[x]. Test creating containers in a vlan.
[]. create vms
[]. Implement migratable mounts that are copied from one node to the other when a service is moved. mounts can be identified using a fixed id for non-epheraml data.
[]. implement disk partitioning using lvm and implement moving using built in lvm features.
[]. generate a better minimal iso with the right ssh access.
[]. Add deployment order dependency if possible.
[]. Grow and shrink LVS based on updated values. Require user action if the LVS was shrunk!
[x]. service.networking similar to hardware.networking ?
[]. modify systemd-resolved to disable fallback servers. Maybe disable stub resolver.
[x]. host side vbridge interfaces for containers should have minimal vlan access. A service in untagged vlan 10 should be attached to a veth interface on host that also only allows vlan10.
