{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hardware.vfio;
  vfioModules = [
    "vfio"
    "vfio_pci"
    "vfio_iommu_type1"
  ];
in
{
  options.${namespace}.hardware.vfio = with types; {
    enable = mkBoolOpt false "Whether or not to enable IOMMU and VFIO PCI passthrough support";
    iommu = mkOpt (enum [
      "intel"
      "amd"
    ]) "intel" "IOMMU implementation of the host CPU";
    pciIds = mkOpt (listOf (
      strMatching "[0-9a-f]{4}:[0-9a-f]{4}"
    )) [ ] "PCI vendor:device IDs claimed by vfio-pci at boot before any host driver can bind them";
  };

  config = mkIf cfg.enable {
    boot.kernelParams = [
      "iommu=pt"
    ]
    ++ optional (cfg.iommu == "intel") "intel_iommu=on"
    ++ optional (cfg.iommu == "amd") "amd_iommu=on"
    ++ optional (cfg.pciIds != [ ]) "vfio-pci.ids=${concatStringsSep "," cfg.pciIds}";

    boot.kernelModules = vfioModules;
    boot.initrd.kernelModules = mkIf (cfg.pciIds != [ ]) vfioModules;

    boot.extraModprobeConfig = ''
      softdep amdgpu pre: vfio-pci
      softdep nouveau pre: vfio-pci
      softdep nvidia pre: vfio-pci
      softdep snd_hda_intel pre: vfio-pci
    '';

    services.udev.extraRules = ''
      SUBSYSTEM=="vfio", GROUP="kvm", MODE="0660"
      KERNEL=="vhost-net", GROUP="kvm", MODE="0660"
    '';
  };
}
