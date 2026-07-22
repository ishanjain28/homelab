_:
let
  genBridgedContainer = { name, vlan, config, specialArgs, }: {
    # Generate the container entry
    containers.${name} = {
      autoStart = true;
      privateNetwork = true;
      # Plug into host bridge
      hostBridge = "br0";

      inherit config;
      inherit specialArgs;
    };

    # Container Trunk Port (Host-side of the vbridge)
    systemd.network.networks."30-container-${name}" =
      {
        matchConfig.Name = "vb-${name}";
        networkConfig.Bridge = "br0";
        bridgeVLANs = [{
          VLAN = vlan;
          PVID = vlan;
          EgressUntagged = vlan;
        }];
      };
  };
in { mkBridgedContainer = genBridgedContainer; }
