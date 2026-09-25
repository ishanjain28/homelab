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
  cfg = config.${namespace}.vms;
  vfio = config.${namespace}.hardware.vfio;
  vms = filterAttrs (_name: vm: vm.enable) cfg;

  qemu = pkgs.qemu_kvm;
  ovmf = pkgs.OVMFFull;

  pciAddressType = types.strMatching "[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\\.[0-7]";
  usbIdType = types.strMatching "[0-9a-f]{4}";

  usbDeviceType = types.submodule {
    options = {
      vendorId = mkOption {
        type = usbIdType;
        description = "USB vendor ID (hex, without 0x).";
      };
      productId = mkOption {
        type = usbIdType;
        description = "USB product ID (hex, without 0x).";
      };
    };
  };

  vmType = types.submodule (
    { name, ... }: {
      options = {
        enable = mkEnableOption "virtual machine ${name}";
        autoStart = mkBoolOpt true "Whether to start this virtual machine at boot.";
        runtimeId = mkOption {
          type = types.int;
          description = "Stable UID/GID of the host user that runs this virtual machine.";
        };
        os = mkOpt (types.enum [
          "linux"
          "windows"
        ]) "linux" "Guest OS family; selects clock, power and Hyper-V enlightenment defaults.";
        cpus = mkOpt types.ints.positive 2 "Number of virtual CPUs.";
        memory = mkOpt types.nonEmptyStr "4G" "Guest memory size, in QEMU notation.";
        vlans = mkOption {
          type = types.addCheck (types.nonEmptyListOf (types.ints.between 1 4094)) (vlans: length vlans == length (unique vlans));
          description = "VLANs attached to this virtual machine as untagged access ports; the first is the primary NIC.";
        };
        disks = mkOpt (types.listOf (
          types.strMatching "/dev/.*"
        )) [ ] "Host block devices attached to the guest as SATA disks, in boot order.";
        pciDevices = mkOpt (types.listOf pciAddressType) [ ] "Host PCI functions passed through with vfio-pci.";
        usbDevices =
          mkOpt (types.listOf usbDeviceType) [ ]
            "Host USB devices attached to the guest whenever they are plugged in.";
        extraArgs = mkOpt (types.listOf types.str) [ ] "Additional QEMU arguments.";
      };
    }
  );

  vmUser = name: "vm-${name}";
  tpm = vm: vm.os == "windows";
  tapName = name: vlan: "vm-${name}-${toString vlan}";
  stateDir = name: "vms/${name}";
  runDir = name: "/run/vms/${name}";

  pciSlot = address: builtins.substring 0 10 address;
  pciFunction = address: builtins.substring 11 1 address;
  pciSlots = vm: unique (map pciSlot vm.pciDevices);

  mkPciArgs =
    vm:
    concatLists (
      imap0 (
        index: slot:
        let
          functions = filter (address: pciSlot address == slot) vm.pciDevices;
          rootPort = "rp${toString index}";
        in
        [
          "-device"
          "pcie-root-port,id=${rootPort},bus=pcie.0,chassis=${toString (index + 1)},slot=${toString (index + 1)}"
        ]
        ++ concatMap (address: [
          "-device"
          (concatStringsSep "," (
            [
              "vfio-pci"
              "host=${address}"
              "bus=${rootPort}"
              "addr=00.${pciFunction address}"
            ]
            ++ optional (length functions > 1 && pciFunction address == "0") "multifunction=on"
          ))
        ]) functions
      ) (pciSlots vm)
    );

  mkDiskArgs =
    vm:
    [
      "-device"
      "ich9-ahci,id=ahci"
    ]
    ++ concatLists (
      imap0 (
        index: disk:
        let
          id = "disk${toString index}";
        in
        [
          "-drive"
          "file=${disk},if=none,id=${id},format=raw,cache=none,aio=native,discard=unmap,detect-zeroes=unmap"
          "-device"
          "ide-hd,drive=${id},bus=ahci.${toString index},rotation_rate=1,bootindex=${toString index}"
        ]
      ) vm.disks
    );

  mkNetArgs =
    name: vm:
    concatMap (
      vlan:
      let
        id = "net${toString vlan}";
      in
      [
        "-netdev"
        "tap,id=${id},ifname=${tapName name vlan},script=no,downscript=no,vhost=on"
        "-device"
        "virtio-net-pci,netdev=${id},mac=${mkMacAddress "vm-${name}:${toString vlan}"}"
      ]
    ) vm.vlans;

  mkUsbArgs =
    vm:
    concatMap (device: [
      "-device"
      "usb-host,bus=xhci.0,vendorid=0x${device.vendorId},productid=0x${device.productId}"
    ]) vm.usbDevices;

  osArgs = vm: {
    linux = [
      "-cpu"
      "host,migratable=off"
      "-rtc"
      "base=utc,driftfix=slew"
    ];
    windows = [
      "-cpu"
      (
        "host,migratable=off,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time,hv_synic,hv_stimer,hv_vpindex,hv_runtime,hv_frequencies,hv_reset,hv_tlbflush,hv_ipi"
        + optionalString (vm.pciDevices != [ ]) ",kvm=off,hv_vendor_id=NV43FIX"
      )
      "-rtc"
      "base=localtime,driftfix=slew"
      "-global"
      "kvm-pit.lost_tick_policy=delay"
      "-global"
      "ICH9-LPC.disable_s3=1"
      "-global"
      "ICH9-LPC.disable_s4=1"
    ];
  };

  mkQemuArgs =
    name: vm:
    let
      run = runDir name;
    in
    [
      "-name"
      "guest=${name},debug-threads=on"
      "-machine"
      "q35,accel=kvm,smm=on,usb=off,vmport=off"
      "-smp"
      "${toString vm.cpus},sockets=1,cores=${toString vm.cpus},threads=1"
      "-m"
      vm.memory
      "-nodefaults"
      "-no-user-config"
      "-display"
      "none"
      "-drive"
      "if=pflash,format=raw,unit=0,readonly=on,file=${ovmf.firmware}"
      "-drive"
      "if=pflash,format=raw,unit=1,file=/var/lib/${stateDir name}/OVMF_VARS.fd"
    ]
    ++ [
      "-global"
      "driver=cfi.pflash01,property=secure,value=on"
    ]
    ++ (osArgs vm).${vm.os}
    ++ [
      "-chardev"
      "socket,id=monitor,path=${run}/monitor.sock,server=on,wait=off"
      "-mon"
      "chardev=monitor,mode=readline"
      "-qmp"
      "unix:${run}/qmp.sock,server=on,wait=off"
      "-chardev"
      "socket,id=qga,path=${run}/qga.sock,server=on,wait=off"
      "-device"
      "virtio-serial-pci"
      "-device"
      "virtserialport,chardev=qga,name=org.qemu.guest_agent.0"
      "-device"
      "virtio-rng-pci"
      "-device"
      "qemu-xhci,id=xhci"
    ]
    ++ optionals (tpm vm) [
      "-chardev"
      "socket,id=chrtpm,path=${run}/swtpm.sock"
      "-tpmdev"
      "emulator,id=tpm0,chardev=chrtpm"
      "-device"
      "tpm-tis,tpmdev=tpm0"
    ]
    ++ mkDiskArgs vm
    ++ mkPciArgs vm
    ++ mkUsbArgs vm
    ++ mkNetArgs name vm
    ++ vm.extraArgs;

  mkPrepareScript =
    name: vm:
    pkgs.writeShellScript "vm-${name}-prepare" ''
      set -euo pipefail

      for dev in ${escapeShellArgs vm.pciDevices}; do
        sysdev="/sys/bus/pci/devices/$dev"
        if [ ! -e "$sysdev" ]; then
          echo "PCI device $dev is not present on this host" >&2
          exit 1
        fi
        if [ -e "$sysdev/driver" ]; then
          driver="$(basename "$(readlink "$sysdev/driver")")"
          if [ "$driver" != vfio-pci ]; then
            echo "$dev" > "$sysdev/driver/unbind"
          fi
        fi
        echo vfio-pci > "$sysdev/driver_override"
        if [ ! -e "$sysdev/driver" ]; then
          echo "$dev" > /sys/bus/pci/drivers_probe
        fi
      done

      for dev in ${escapeShellArgs vm.pciDevices}; do
        sysdev="/sys/bus/pci/devices/$dev"
        group="$(basename "$(readlink "$sysdev/iommu_group")")"
        for member in "$sysdev"/iommu_group/devices/*; do
          address="$(basename "$member")"
          [ "$address" = "$dev" ] && continue
          case "$(cat "$member/class")" in 0x0604*) continue ;; esac
          driver="$(basename "$(readlink "$member/driver" 2>/dev/null || echo none)")"
          case "$driver" in none | vfio-pci | pcieport | pci-stub) continue ;; esac
          echo "IOMMU group $group member $address is bound to $driver; it must also be passed through or unbound" >&2
          exit 1
        done
        for _ in $(seq 1 50); do
          [ -e "/dev/vfio/$group" ] && break
          sleep 0.2
        done
        chgrp kvm "/dev/vfio/$group"
        chmod 0660 "/dev/vfio/$group"
      done

      for disk in ${escapeShellArgs vm.disks}; do
        device="$(readlink -f "$disk")"
        if [ ! -b "$device" ]; then
          echo "Disk $disk is not a block device" >&2
          exit 1
        fi
        setfacl -m "u:${vmUser name}:rw" "$device"
      done

      for tap in ${escapeShellArgs (map (tapName name) vm.vlans)}; do
        for _ in $(seq 1 50); do
          [ -e "/sys/class/net/$tap" ] && break
          sleep 0.2
        done
        if [ ! -e "/sys/class/net/$tap" ]; then
          echo "Tap interface $tap was not created by systemd-networkd" >&2
          exit 1
        fi
      done

      ${optionalString (tpm vm) ''
        for _ in $(seq 1 50); do
          [ -S "${runDir name}/swtpm.sock" ] && break
          sleep 0.2
        done
        if [ ! -S "${runDir name}/swtpm.sock" ]; then
          echo "swtpm socket for ${name} is not available" >&2
          exit 1
        fi
      ''}
    '';

  mkFirmwareScript =
    name: _vm:
    pkgs.writeShellScript "vm-${name}-firmware" ''
      set -euo pipefail
      vars="$STATE_DIRECTORY/OVMF_VARS.fd"
      if [ ! -e "$vars" ]; then
        install -m 0600 ${ovmf.variablesMs} "$vars"
      fi
    '';

  mkStopScript =
    name: _vm:
    pkgs.writeShellScript "vm-${name}-stop" ''
      set -uo pipefail
      if [ -S "${runDir name}/qmp.sock" ]; then
        {
          printf '{"execute":"qmp_capabilities"}\n{"execute":"system_powerdown"}\n'
          sleep 1
        } | socat - "UNIX-CONNECT:${runDir name}/qmp.sock" > /dev/null 2>&1 || true
      fi
      while kill -0 "$MAINPID" 2>/dev/null; do
        sleep 1
      done
    '';

  mkVm = name: vm: {
    users.users.${vmUser name} = {
      isSystemUser = true;
      uid = vm.runtimeId;
      group = vmUser name;
      extraGroups = [ "kvm" ];
    };
    users.groups.${vmUser name}.gid = vm.runtimeId;

    systemd.network.netdevs = listToAttrs (
      map (
        vlan:
        nameValuePair "20-${tapName name vlan}" {
          netdevConfig = {
            Name = tapName name vlan;
            Kind = "tap";
          };
          tapConfig = {
            User = vmUser name;
            Group = "kvm";
            VNetHeader = true;
          };
        }
      ) vm.vlans
    );

    systemd.network.networks = listToAttrs (
      map (
        vlan:
        nameValuePair "30-${tapName name vlan}" {
          matchConfig.Name = tapName name vlan;
          networkConfig.Bridge = "br0";
          linkConfig.RequiredForOnline = "no";
          bridgeVLANs = [
            {
              VLAN = vlan;
              PVID = vlan;
              EgressUntagged = vlan;
            }
          ];
        }
      ) vm.vlans
    );

    services.udev.extraRules = concatMapStringsSep "\n" (
      device:
      ''SUBSYSTEM=="usb", ATTR{idVendor}=="${device.vendorId}", ATTR{idProduct}=="${device.productId}", GROUP="kvm", MODE="0660"''
    ) vm.usbDevices;

    systemd.services."vm-${name}-swtpm" = mkIf (tpm vm) {
      description = "Emulated TPM for virtual machine ${name}";
      partOf = [ "vm-${name}.service" ];
      serviceConfig = {
        User = vmUser name;
        Group = vmUser name;
        StateDirectory = "${stateDir name}/tpm";
        StateDirectoryMode = "0700";
        RuntimeDirectory = stateDir name;
        RuntimeDirectoryPreserve = "yes";
        ExecStart = "${pkgs.swtpm}/bin/swtpm socket --tpm2 --tpmstate dir=/var/lib/${stateDir name}/tpm --ctrl type=unixio,path=${runDir name}/swtpm.sock --log level=1";
        Restart = "on-failure";
        RestartSec = "2s";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
      };
    };

    systemd.services."vm-${name}" = {
      description = "Virtual machine ${name}";
      wantedBy = optional vm.autoStart "multi-user.target";
      after = [
        "systemd-networkd.service"
        "network-online.target"
      ]
      ++ optional (tpm vm) "vm-${name}-swtpm.service";
      wants = [ "network-online.target" ];
      requires = optional (tpm vm) "vm-${name}-swtpm.service";
      path = with pkgs; [
        acl
        coreutils
        socat
      ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        User = vmUser name;
        Group = vmUser name;
        SupplementaryGroups = [ "kvm" ];
        StateDirectory = stateDir name;
        StateDirectoryMode = "0700";
        RuntimeDirectory = stateDir name;
        RuntimeDirectoryPreserve = "yes";
        ExecStartPre = [
          "+${mkPrepareScript name vm}"
          (mkFirmwareScript name vm)
        ];
        ExecStart = "${qemu}/bin/qemu-system-x86_64 ${escapeShellArgs (mkQemuArgs name vm)}";
        ExecStop = mkStopScript name vm;
        TimeoutStartSec = "2min";
        TimeoutStopSec = "3min";
        Restart = "on-failure";
        RestartSec = "5s";
        LimitMEMLOCK = "infinity";
        LimitNOFILE = 1048576;
        OOMScoreAdjust = -500;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
      };
    };
  };

  tapNames = flatten (mapAttrsToList (name: vm: map (tapName name) vm.vlans) vms);
  longTapNames = filter (tap: stringLength tap > 15) tapNames;
  vmsWithoutStorage = attrNames (filterAttrs (_name: vm: vm.disks == [ ] && vm.pciDevices == [ ]) vms);
  vmsWithPci = attrNames (filterAttrs (_name: vm: vm.pciDevices != [ ]) vms);
  runtimeIds = mapAttrsToList (_name: vm: vm.runtimeId) vms;
  vmConfigs = mapAttrsToList mkVm vms;
in
{
  options.${namespace}.vms = mkOpt (types.attrsOf vmType) { } "QEMU virtual machines hosted on this machine.";

  config = {
    assertions = [
      {
        assertion = longTapNames == [ ];
        message = "Virtual machine tap interface names exceed 15 characters: ${concatStringsSep ", " longTapNames}";
      }
      {
        assertion = vmsWithoutStorage == [ ];
        message = "Virtual machines have neither disks nor PCI devices to boot from: ${concatStringsSep ", " vmsWithoutStorage}";
      }
      {
        assertion = vmsWithPci == [ ] || vfio.enable;
        message = "Virtual machines pass through PCI devices but homelab.hardware.vfio is not enabled: ${concatStringsSep ", " vmsWithPci}";
      }
      {
        assertion = length runtimeIds == length (unique runtimeIds);
        message = "Virtual machine runtimeIds must be unique on a host.";
      }
    ];

    environment.systemPackages = mkIf (vms != { }) [
      qemu
      pkgs.socat
    ];

    boot.kernelModules = mkIf (vms != { }) [ "vhost_net" ];

    users.users = mkMerge (map (vm: vm.users.users) vmConfigs);
    users.groups = mkMerge (map (vm: vm.users.groups) vmConfigs);
    systemd.network.netdevs = mkMerge (map (vm: vm.systemd.network.netdevs) vmConfigs);
    systemd.network.networks = mkMerge (map (vm: vm.systemd.network.networks) vmConfigs);
    systemd.services = mkMerge (map (vm: vm.systemd.services) vmConfigs);
    services.udev.extraRules = concatStringsSep "\n" (map (vm: vm.services.udev.extraRules) vmConfigs);
  };
}
