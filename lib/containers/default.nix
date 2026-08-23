let
  isolationProfiles = {
    unprivileged = {
      privateUsers = 100000;
    };

    privileged = {
      privateUsers = false;
    };
  };

  hardeningProfiles = rec {
    default = {
      NoNewPrivileges = true;
      AmbientCapabilities = "";
      CapabilityBoundingSet = "";
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
      RemoveIPC = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      UMask = "0077";
    };

    network-monitor = default // {
      AmbientCapabilities = "CAP_NET_RAW";
      CapabilityBoundingSet = "CAP_NET_RAW";
    };

    device-access = default // {
      PrivateDevices = false;
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
