{ pkgs }:
let
  inherit (pkgs) lib;
  rules = import ./rules.nix { inherit lib; };
  lifecycle =
    (import ./module.nix {
      nixpkgs = pkgs.path;
      system = pkgs.stdenv.hostPlatform.system;
    }).config.systemd.services;
  files = lib.mapAttrs (name: text: pkgs.writeText "firewall-${name}.nft" text) rules;
in
pkgs.testers.runNixOSTest {
  name = "homelab-service-firewall";
  requiredFeatures.kvm = false;
  nodes.machine = {
    boot.kernelModules = [ "nf_conntrack_bridge" ];
    users.users.tester = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.systemPackages = [
      pkgs.python3
      pkgs.iproute2
      pkgs.nftables
      pkgs.util-linux
    ];
    virtualisation.memorySize = 768;
    virtualisation.graphics = false;
    # Exercise the generated NixOS firewall transaction and unit dependency graph.
    # The stand-in process isolates lifecycle testing from nspawn guest boot costs.
    systemd.services = {
      nftables.serviceConfig = lib.getAttrs [
        "ExecStart"
        "ExecStartPost"
        "ExecReload"
        "ExecStop"
        "Type"
        "RemainAfterExit"
        "StateDirectory"
      ] lifecycle.nftables.serviceConfig;
      "container@a" = {
        inherit (lifecycle."container@a") requires bindsTo after;
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        };
      };
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    with subtest("generated firewall lifecycle"):
        machine.succeed("systemctl start container@a.service")
        machine.wait_for_unit("nftables.service")
        machine.succeed("nft list table bridge homelab_services")
        machine.succeed("systemctl reload nftables.service")
        machine.succeed("systemctl stop nftables.service")
        machine.fail("systemctl is-active --quiet container@a.service")
        machine.succeed("nft list table bridge homelab_services")
        machine.succeed("mkdir -p /run/systemd/system/nftables.service.d")
        machine.succeed("printf '[Service]\\nExecStart=\\nExecStart=/run/current-system/sw/bin/false\\n' > /run/systemd/system/nftables.service.d/fail.conf")
        machine.succeed("systemctl daemon-reload")
        machine.fail("systemctl start container@a.service")
        machine.fail("systemctl is-active --quiet container@a.service")
        machine.succeed("nft list table bridge homelab_services")
        machine.succeed("rm /run/systemd/system/nftables.service.d/fail.conf; systemctl daemon-reload; systemctl reset-failed")
        machine.succeed("systemctl start container@a.service")
        machine.succeed("systemctl restart nftables.service")
        machine.wait_for_unit("container@a.service")
        firewall_started = int(machine.succeed("systemctl show -p ActiveEnterTimestampMonotonic --value nftables.service"))
        container_started = int(machine.succeed("systemctl show -p ActiveEnterTimestampMonotonic --value container@a.service"))
        assert container_started >= firewall_started
        machine.succeed("nft list table bridge homelab_services")
    machine.succeed("su -s /bin/sh tester -c 'unshare -Urn python3 ${./netns.py} ${files.allow} ${files.revoke} ${files.audit}'")
  '';
}
