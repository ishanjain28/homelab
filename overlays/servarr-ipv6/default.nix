_inputs: _final: prev:
let
  keepIpv6 =
    package:
    package.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/NzbDrone.Common/Http/Dispatchers/ManagedHttpDispatcher.cs \
          --replace-fail 'useIPv6 = !routableIPv4;' 'useIPv6 = true;'
      '';
    });
in
{
  sonarr = keepIpv6 prev.sonarr;
  radarr = keepIpv6 prev.radarr;
  lidarr = keepIpv6 prev.lidarr;
}
