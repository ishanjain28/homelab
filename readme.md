# Homelab

My previous homelab was built on top of 3 Proxmox nodes. A large majority of applications were deployed into LXC containers and a few were deployed into VMs.
This setup was bootstrapped and configured a set of Ansible scripts that I was never quite happy with. It evolved over ~7 years and there were always some environments
that were better configured than others.

This is an attempt to fix all of that and get a more uniform flow for application enironments, logging, monitoring, persistent volumes, security and networking.


## Generating the bootstrap ISO for installation

You can technically use nixos iso but I prefer generating a minimal ISO which has all the tools I need with my SSH key configured and overall designed to be remotely bootstrappable.

```console
nix build .#install-isoConfigurations.minimal
```

### Configuring nodes from Minimal Nix ISO

#### Generating machine hardware and disk configuration

1. We need the disk config and hardware configuration for the new machine. This needs careful manual inspection and you can
get the initial draft by running `sudo nixos-generate-config  --show-hardware-config` on the machine.

Run this to get the detailed disk data, import any existing file systems.

```
lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS
ls -l /dev/disk/by-id/ | grep -v part
sudo pvs; sudo vgs; sudo lvs
```

Add `filesystems.<mountpoints>` by specifying the path to device by-id and fsType.

For ZFS, add the following config and each dataset in the pool will be mounted after boot.
```
boot.supportedFilesystems.zfs = true
boot.zfs.extraPools = [ "<pool-name>" ]
boot.kernelPackages = pkgs.linuxPackages
services.zfs.autoScrub.enable = true;
```

ZFS uses `/etc/machine-id` data to ensure the same pool is not mounted on 2 systems. The pool will fail to import on the new machine and to fix that you need to
run `sudo zpool import -f <pool-name>` as a 1 time fix to update the captured machine-id.


Run the command below to copy persistent volumes data from the previous machine.
This copies everything and preserves uid/gid on the content.
```
sudo rsync -aHAX --numeric-ids --delete --info=progress2 \
  root@<old-machine-ip>:/mnt/backup/volumes/ /var/lib/volumes/
```

Copying VM thick LVM volumes

Create a raw copy of the LVM volume using
```
# For the example volume is called vm-143-0
cd backups
ssh ishan@<previous-server-address> 'zstd -1 -T0 -c /main/backups/vms/vm-143-0.raw' | zstd -d |  sudo dd of=/dev/pool/vm-143-0 bs=4M iflag=fullblock status=progress conv=fsync
```

Restore it into an identical thick LVM volume using
```
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
```
echo "grub-efi-amd64 grub2/force_efi_extra_removable boolean true" | sudo debconf-set-selections
sudo dpkg-reconfigure -f noninteractive grub-efi-amd64
```

2. Networking

I love predictable network interface names. Get the MAC addresses of interfaces and update `default.nix` with the interface names in `mkIfLink`.
Update rest of the networking as needed.

3. Workloads and volumes

Add the services that should run on this instance and the volumes the services need. Volumes are created as thick LVM volumes on the
LVM specified in disk-config for the system with the assumption the PV is just called `pool`.


4. Deploy!

This assumes the machine to configure is called `tomato`. Use `nixos-anywhere` to configure the node.

```console
nix run github:nix-community/nixos-anywhere -- --flake .#tomato ishan@<address>
```

Deploying from aarch64 to x64? Install `qemu-user-static`, add `extra-platforms = x86_64-linux` to `/etc/nix/nix.conf`, restart nix-daemon and then deploy.

The persistent volumes are created on the initial deployment but services will fail to start because the secrets are encrypted with a different key. It uses SSH key on the host to encrypt credentials.
This ssh key is generated on deployment and is not part of the repo. Optionally, It can be specified using `sshKeyFile`.
After deployment copy the generaated public key from the host(from `/etc/ssh/ssh_host_ed25519_key.pub`) and update all the secrets using `echo '<key>' | nix run nixpkgs#ssh-to-age`.
Add the key in `.sops.yaml` and then run `find secrets -type f -exec sops updatekeys -y {} \;` to update all the secrets.


## Homes

Home-manager configs live in `homes/<system>/<user>@<name>`. `home-manager` is available in the dev shell.

```console
nix develop
home-manager switch --flake .#<user>@<home> -b backup
```

`-b backup` renames existing files in the way (e.g. `~/.zshrc` → `~/.zshrc.backup`) instead of failing. Only needed on the first switch.


## Features



## TODO Notes

* Generate caddy config from services config.

I am not sure if I am actually going to implement this. I don't believe in security by obscurity but I do like to keep the domain names private just to avoid bot traffic.
I tried caddy config generation directly from service definition but I also need to specify the domain there which will be in plain text and part of the repo. In future, I will likely
still add config generation but keep the domain and maybe some other fields private in a secret.

* Maybe generate dnsconfig.js from services data.

My dnsconfig.js config generates DNS entries that go in Cloudflare for public access, the internal DNS servers with overrides so the same domains resolve to internal addresses rather than public
address in cloudflare and then more DNS entries for internal services and devices.

* Add deployment order dependency if possible. Already done for some situations like waiting for postgres to be online before starting a service that relies on postgres but this is specific to situation and there is no general deployment DAG.

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

* Alerting system when something fails. Backups, healthchecks

* Windmill working with an email receiver. Ideally, I want to do an IMAP server just for this rather than giving it limited access to some other email account. This can be IPv6 only in my ASN and IPv6 only is fine in this context.

* Credit card / Bank statement processing pipeline in windmill to auto save them to actual budget. This is also done but the work is separate and was deployed to windmill directly.

* MAC address for services is created from a hash of <svc-name>:<vlan-id>. A service with the exact same name deployed on 2 machines will have a conflict. I don't want this to be a hard error because this repo will deploy
services on machines that are on completely different networks but maybe there should be a warning.

* Auto-provision grafana dashboards from dashboards/ folder.

### remote bootstrap Notes

1. got stuck on /dev/disk/by-label/nixos-minimal-26.11-x86_64 when booting with the virtual media option in jetkvm. FIX: Needs to be mounted as CD/DVD for it to show up in boot options and then mounted as disk not as cd/dvd for it to show up in /dev/disk/by-label/nix... This was a bug in JetKVM firmware.

2. did not request an ip address using dhcp, did not use slaac for auto assignment. TODO: Machine should have a fallback address maybe 192.168.1.254 ? PROBLEM: The other side was only allowing vlan tagged traffic and bootstrap nix only works with untagged traffic.
