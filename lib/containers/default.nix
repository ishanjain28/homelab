let
  containerProfiles = {
    unprivileged = {
      privateUsers = 131072;
      extraFlags = [ "--private-users-ownership=chown" ];
    };

    privileged = {
      privateUsers = "no";
    };
  };

  serviceProfiles = rec {
    minimal = {
      NoNewPrivileges = true;
      AmbientCapabilities = [ ];
      CapabilityBoundingSet = [ ];
      RemoveIPC = true;
      SystemCallArchitectures = "native";
      UMask = "0077";
    };

    default = minimal // {
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "full";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallErrorNumber = "EPERM";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
    };

    # SystemCallArchitectures strips CAP_SETUID from root services, which smbd needs to impersonate users.
    file-server = builtins.removeAttrs minimal [ "SystemCallArchitectures" ] // {
      CapabilityBoundingSet = [
        "CAP_CHOWN"
        "CAP_DAC_OVERRIDE"
        "CAP_DAC_READ_SEARCH"
        "CAP_FOWNER"
        "CAP_FSETID"
        "CAP_KILL"
        "CAP_LEASE"
        "CAP_NET_BIND_SERVICE"
        "CAP_SETGID"
        "CAP_SETUID"
        "CAP_SYS_RESOURCE"
      ];
    };

    device-access = minimal // {
      ProtectHome = false;
    };

    nesting = minimal // {
      RestrictNamespaces = false;
    };

    trusted-debug = {
      NoNewPrivileges = true;
      LockPersonality = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
    };

    unconfined = { };
    privileged = unconfined;
    media = device-access;
  };

  grant = capability: {
    AmbientCapabilities = [ capability ];
    CapabilityBoundingSet = [ capability ];
  };

  serviceTraits = {
    jit.MemoryDenyWriteExecute = false;
    procfs.ProcSubset = "all";
    setuid.SystemCallFilter = [ "@setuid" ];
    privileged-ports = grant "CAP_NET_BIND_SERVICE";
    raw-sockets = grant "CAP_NET_RAW";
    browser = {
      MemoryDenyWriteExecute = false;
      RestrictNamespaces = false;
      SystemCallFilter = [
        "capset"
        "chroot"
        "mincore"
      ];
    };
  };

  addTrait =
    profile: trait:
    profile
    // builtins.mapAttrs (name: value: if builtins.isList value then profile.${name} or [ ] ++ value else value) trait;

  capabilitiesToString =
    profile:
    profile
    // builtins.mapAttrs (_: builtins.concatStringsSep " ") (
      builtins.intersectAttrs {
        AmbientCapabilities = null;
        CapabilityBoundingSet = null;
      } profile
    );

  getServiceProfile =
    names:
    let
      list = if builtins.isList names then names else [ names ];
      base = if serviceProfiles ? ${builtins.head list} then builtins.head list else "default";
      traits = map (name: serviceTraits.${name} or (throw "Unknown service profile '${name}'")) (
        builtins.filter (name: name != base) list
      );
    in
    capabilitiesToString (builtins.foldl' addTrait serviceProfiles.${base} traits);

  getContainerProfile = name: containerProfiles.${name} or (throw "Unknown container profile '${name}'");
in
{
  inherit getContainerProfile getServiceProfile;
}
