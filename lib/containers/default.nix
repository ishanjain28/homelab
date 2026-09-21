let
  isolationProfiles = {
    unprivileged = {
      privateUsers = 131072;
      extraFlags = [ "--private-users-ownership=chown" ];
    };

    privileged = {
      privateUsers = "no";
    };
  };

  hardeningProfiles = rec {
    default = {
      NoNewPrivileges = true;
      AmbientCapabilities = "";
      CapabilityBoundingSet = "";
      RemoveIPC = true;
      SystemCallArchitectures = "native";
      UMask = "0077";
    };

    strict = default // {
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
    };

    network-monitor = default // {
      AmbientCapabilities = "CAP_NET_RAW";
      CapabilityBoundingSet = "CAP_NET_RAW";
    };

    privileged-ports = default // {
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
    };

    # SystemCallArchitectures strips CAP_SETUID from root services, which smbd needs to impersonate users.
    file-server = builtins.removeAttrs default [ "SystemCallArchitectures" ] // {
      CapabilityBoundingSet = "CAP_CHOWN CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH CAP_FOWNER CAP_FSETID CAP_KILL CAP_LEASE CAP_NET_BIND_SERVICE CAP_SETGID CAP_SETUID CAP_SYS_RESOURCE";
    };

    device-access = default // {
      ProtectHome = false;
    };

    nesting = default // {
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

  getProfile =
    kind: profiles: profile:
    profiles.${profile} or (throw "Unknown ${kind} profile '${profile}'");
in
{
  nspawnHardeningProfiles = hardeningProfiles;
  nspawnIsolationProfiles = isolationProfiles;

  getNspawnHardeningProfile = getProfile "service hardening" hardeningProfiles;
  getNspawnIsolationProfile = getProfile "container isolation" isolationProfiles;
}
