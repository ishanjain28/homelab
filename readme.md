# Homelab

My previous homelab was built on top of 3 Proxmox nodes. A large majority of applications were deployed into LXC containers and a few were deployed into VMs.
This setup was bootstrapped and configured a set of Ansible scripts that I was never quite happy with. It evolved over ~7 years and there were always some environments
that were better configured than others.

This is an attempt to fix all of that and get a more uniform flow for application enironments, logging, monitoring, persistent volumes, security and networking.


## Systems

| System | Location | Hardware | Runs |
|---|---|---|---|
| annapurna | Home | Intel i5 12400, 2TB WD SN570 NVMe (OS, service volumes), 3×10TB Seagate Exos in ZFS raidz1 + 1 separate 10TB Seagate Exos, 4TB WD | Media (jellyfin, sonarr, radarr, lidarr, prowlarr, bazarr, unpackerr, qbittorrent, seerr, tracearr), samba, ingress caddy, adguardhome, authelia, lldap, stalwart, gitea, windmill, karakeep, nitter, omada, bentopdf, PostgreSQL primary and Delhi mirror, grafana, loki, victoriametrics, alloy-syslog, telegraf-snmp, VLAN debug containers |
| kepler | Home | Proxmox VM (temporary) | actual, backrest, changedetection, cups, garmin-sync, gitea-runner, huawei-sms, mathesar, multicaster, openvscode-server, pvr-movies-monitor, ripe-atlas probes |
| kanchenjunga | Home | AMD 5900x, 1TBx2 Samsung 970 EVO Plus NVMe, 2TB WD SN750, VFIO passthrough | VMs: win10, work |
| manaslu | Delhi | Vultr VPS, 1 core, 2GB memory | BIRD, WireGuard, caddy, adguardhome, gatus, vaultwarden, freshrss, znc, PostgreSQL primary |
| vaalserberg | Amsterdam | iFog VPS | BIRD (BGP with iFog) |
| minimal | — | x86_64 install ISO | Bootstrap image for new machines |

Every host also runs ssh, tailscale and chrony.


## Generating the bootstrap ISO for installation

You can technically use nixos iso but I prefer generating a minimal ISO which has all the tools I need with my SSH key configured and overall designed to be remotely bootstrappable.

```console
nix build .#install-isoConfigurations.minimal
```

### Configuring nodes from Minimal Nix ISO

#### Generating machine hardware and disk configuration

1. The disk config and hardware configuration for the new machine. This needs careful manual inspection and you can
get the initial draft by running `sudo nixos-generate-config  --show-hardware-config` on the machine.

Run this to get the detailed disk data, import any existing file systems.

```bash
lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS
ls -l /dev/disk/by-id/ | grep -v part
sudo pvs; sudo vgs; sudo lvs
```

Add `filesystems.<mountpoints>` by specifying the path to device by-id and fsType.

For ZFS, add the following config and each dataset in the pool will be mounted after boot.
```nix
boot.supportedFilesystems.zfs = true
boot.zfs.extraPools = [ "<pool-name>" ]
boot.kernelPackages = pkgs.linuxPackages
services.zfs.autoScrub.enable = true;
```

ZFS uses `/etc/machine-id` data to ensure the same pool is not mounted on 2 systems. The pool will fail to import on the new machine and to fix that you need to
run `sudo zpool import -f <pool-name>` as a 1 time fix to update the captured machine-id.


Run the command below to copy persistent volumes data from the previous machine.
This copies everything and preserves uid/gid on the content.
```bash
sudo rsync -aHAX --numeric-ids --delete --info=progress2 \
  root@<old-machine-ip>:/mnt/backup/volumes/ /var/lib/volumes/
```

Copying VM thick LVM volumes

Create a raw copy of the LVM volume using
```bash
# For the example, volume is called vm-143-0
cd backups
ssh ishan@<previous-server-address> 'zstd -1 -T0 -c /main/backups/vms/vm-143-0.raw' | zstd -d |  sudo dd of=/dev/pool/vm-143-0 bs=4M iflag=fullblock status=progress conv=fsync
```

Restore it into an identical thick LVM volume using
```bash
stat -c %s vm-143-0  # Alternatively, you can also get size in bytes using ls -al
12345678

# On the new machine
sudo lvcreate -L 12345678b -n vm-143-0 pool
ssh ishan@<backup-server-addr> 'cat /main/backups/vms/vm-143-0.raw' | sudo dd of=/dev/pool/vm-143-0 bs=4M iflag=fullblock status=progress conv=fsync
```

Fixing UEFI boot for VMs migrated from Proxmox

Proxmox keeps the UEFI boot entries in a separate small EFI disk(`efidisk0`, the ~4MiB volume that starts with `_FVH`). That is OVMF NVRAM, not a disk, so don't copy it and
don't add it to `disks`. The VM module creates a fresh `OVMF_VARS.fd` in `/var/lib/vms/<name>/` that has no boot entry for the guest OS, and Debian does not install the fallback
`\EFI\BOOT\BOOTX64.EFI` by default. The VM sits in the firmware forever and it looks like networking is broken because the guest never sends any traffic.
Confirm it with `info registers` on `/run/vms/<name>/monitor.sock`. `RIP` in the `0x7xxxxxxx` range means it is still in the firmware, a booted kernel will be at `0xffffffff...`.

Fix it by copying shim into the fallback path along with `fbx64.efi`. On the first boot, shim runs `fbx64.efi` which reads `EFI/debian/BOOTX64.CSV`, recreates the boot entry in NVRAM and reboots.
```bash
sudo systemctl stop vm-work
LOOP=$(sudo losetup -fP --show /dev/pool/work-linux-1)
sudo mount ${LOOP}p1 /mnt
sudo mkdir -p /mnt/EFI/BOOT
sudo cp /mnt/EFI/debian/shimx64.efi /mnt/EFI/BOOT/BOOTX64.EFI
sudo cp /mnt/EFI/debian/{fbx64,mmx64,grubx64}.efi /mnt/EFI/BOOT/
sudo umount /mnt && sudo losetup -d $LOOP
```

After it boots, run this in the guest so grub/shim upgrades keep the fallback copy updated.
```bash
echo "grub-efi-amd64 grub2/force_efi_extra_removable boolean true" | sudo debconf-set-selections
sudo dpkg-reconfigure -f noninteractive grub-efi-amd64
```

2. Networking

I love predictable network interface names! Get the MAC addresses of interfaces and update `default.nix` with the interface names in `mkIfLink`.
Update rest of the networking as needed.

3. Workloads and volumes

Add the services that should run on this instance and the volumes services need. Volumes are created as thick LVM volumes on the
PV specified in disk-config for the system with the assumption the PV is just called `pool`.


4. Deploy!

This assumes the machine to configure is called `tomato`. Use `nixos-anywhere` to configure the node.

```console
nix run github:nix-community/nixos-anywhere -- --flake .#tomato <user>@<address>
```

Deploying from aarch64 to x64? Install `qemu-user-static`, add `extra-platforms = x86_64-linux` to `/etc/nix/nix.conf`, restart nix-daemon and then deploy. This does not always work because
`qemu-user-static` can sometimes crash. In that situation, you can use `--remote-build` flag in `deploy-rs`.

The persistent volumes are created on the initial deployment but services will fail to start because the secrets are encrypted with a different key. It uses SSH key on the host to encrypt credentials.
This ssh key is generated on deployment and is not part of the repo. Optionally, It can be specified using `sshKeyFile`.
After deployment copy the generated public key from the host(from `/etc/ssh/ssh_host_ed25519_key.pub`) and update all the secrets using `echo '<key>' | nix run nixpkgs#ssh-to-age`.
Add the key in `.sops.yaml` and then run `find secrets -type f -exec sops updatekeys -y {} \;` to update all the secrets.

Google Drive backups: the remote must be called `gdrive`; every host reads `secrets/backups/rclone.conf`.
```console
rclone config create gdrive drive scope=drive.file --config secrets/backups/rclone.conf
sops -e -i secrets/backups/rclone.conf
```

Moving a service between hosts: declare it (same `runtimeId`, same volume `uuid`/`size`) on the target as `disabled`, deploy both, then on the target run `sudo volume pull <service> --from <user>@<source>`; enable it on the target, deploy, remove it from the source and `lvremove` the old LVs.


## Homes

Home-manager configs live in `homes/<system>/<user>@<name>`. `home-manager` is available in the dev shell.

```console
nix develop
home-manager switch --flake .#<user>@<home> -b backup
```

`-b backup` renames existing files in the way (e.g. `~/.zshrc` → `~/.zshrc.backup`) instead of failing. Only needed on the first switch.


## Features

**Deployment**
* One flake (snowfall-lib) for every host, home and package; deploy-rs with magic rollback. Rolls back if the SSH connection to machine breaks after deployment.
* Bootstrap ISO and disko disk layouts for installing new machines.
* systemd-boot boot assessment: a new generation is only blessed once SSH comes up, otherwise the host reboots into the previous one. Optional Secure Boot through lanzaboote.
* Remote rescue baseline: hardware watchdog, reboot on panic or failed boot, Tailscale always on.
* Weekly `nh clean`, store optimisation and binary cache substitution on every host.

**Service containers**
* Every service runs in its own systemd-nspawn container with a private user namespace.
* Containers attach to one or more VLANs on a VLAN-aware bridge. On `manaslu`, there are no vlans and services share the host network.
* Stable MAC per service and VLAN, derived from the name, so DHCP leases and SLAAC IPv6 addresses never change. Hosts get the same treatment for their management interface.
* The container firewall only opens the endpoints a service declares.
* CPU, memory and task limits per container.
* systemd sandbox profiles for every service unit, composable with traits (`jit`, `privileged-ports`, `raw-sockets`, `procfs`, `setuid`, `browser`).
* Secrets are decrypted on the host with sops-nix and bind-mounted read-only into the container that needs them; changing a secret restarts that container.
* Wildcard certificates issued with lego over DNS and handed to the containers that ask for them.
* Host devices (GPU render node) and shared filesystems (ZFS datasets, disks) attached per service with fixed group IDs.

**Data**
* Persistent volumes are LVM logical volumes identified by filesystem UUID, created and grown on deploy and mounted into the owning container.
* `volume pull` moves a service's volumes from one host to another.
* PostgreSQL instances whose databases, roles and grants come from one secret file; streaming replication between Delhi and home; services wait for their database and stop before it.
* Restic backups per volume, grouped by schedule and retention, to a local repository and Google Drive, with scheduled prune and check.

**Observability**
* Telegraf on every host: system, SMART and per-container cgroup metrics (plus monitioring of Intel/NVIDIA/AMD GPUs) into VictoriaMetrics. SNMP polling for network gear.
* Alloy ships journald and log files from the home hosts and their containers to Loki; a syslog receiver collects logs from devices.
* Grafana with dashboards provisioned from the repo.
* Gatus health checks generated from each service's declared endpoints, alerting over Pushover and Telegram.
* Pushover alert when any backup fails.

**Networking**
* systemd-networkd with interfaces renamed by permanent MAC.
* WireGuard between home and Delhi, BIRD BGP for announcing my IPv6 prefixes, Tailscale subnet routes.
* QEMU VMs with VFIO PCI and USB passthrough, hugepages and VLAN attachments.

**Hosts and shells**
* Immutable users, SSH keys from `ssh-keys.txt`.
* Fish everywhere with shared aliases and word-wise key bindings, terminfo for kitty, alacritty and ghostty.
* Hard disks spin down every day at 05:00 and only spin up when something reads them.
* Home-manager configurations for workstations, with Neovim.
* Wallpapers synced from a [public Google Photos album](https://photos.app.goo.gl/Cs2szWqUphnaTW8N9) on every home-manager switch.
* Dev shell with deploy-rs, sops and a git diff driver that shows decrypted secrets.


## TODO Notes

* Generate caddy config from services config.

I am not sure if I am actually going to implement this. I don't believe in security by obscurity but I do like to keep the domain names private just to avoid bot traffic.
I tried caddy config generation directly from service definition but I also need to specify the domain there which will be in plain text and part of the repo. In future, I will likely
still add config generation but keep the domain and maybe some other fields private in a secret.

* Maybe generate dnsconfig.js from services data.

My dnsconfig.js config generates DNS entries that go in Cloudflare for public access, the internal DNS servers with overrides so the same domains resolve to internal addresses rather than public
address in cloudflare and then more DNS entries for internal services and devices.

* [PARTIALLY DONE] Grow and shrink LVS based on updated values. Require user action if the LVS was shrunk!

* Introduce firewall in the networking stack maybe by using services.firewalld.

* I do not like the requirement to specify IPv4 addresses for services. MAC address are a hash of service name, IPv6 address are autogenerated using SLAAC and advertised prefix using EUI64. IPv6 addresses
are predictable but IPv4 addresses are not. Ideally, I'd like to move the internal communication to V6 only with 464XLAT for outbound V4 communication. I tried this a few years ago but I couldn't do a wider rollout
because Microsoft did not have a PLAT implementation.

* limit the amount of space visible to stateless apps and apps checking disk space outside of the mounted volumes.

* LLDP enabled on hosts permanently. Remote rescue should be easily discoverable.

* gitea runner needs privileged access.

* Specify secrets update policies. Currently, it restarts the service but some services offer a reload option to do it without disrupting the process. In that situation,
it should call the reload command for the service rather than restarting it!

* Windmill working with an email receiver. Ideally, I want to do an IMAP server just for this rather than giving it limited access to some other email account. This can be IPv6 only in my ASN and IPv6 only is fine in this context.

* Credit card / Bank statement processing pipeline in windmill to auto save them to actual budget. This is also done but the work is separate and was deployed to windmill directly.

### remote bootstrap Notes

1. got stuck on /dev/disk/by-label/nixos-minimal-26.11-x86_64 when booting with the virtual media option in jetkvm. FIX: Needs to be mounted as CD/DVD for it to show up in boot options and then mounted as disk not as cd/dvd for it to show up in /dev/disk/by-label/nix... This was a bug in JetKVM firmware.

2. did not request an ip address using dhcp, did not use slaac for auto assignment. TODO: Machine should have a fallback address maybe 192.168.1.254 ? PROBLEM: The other side was only allowing vlan tagged traffic and bootstrap nix only works with untagged traffic.
