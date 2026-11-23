_inputs: _final: prev: {
  lidarr = prev.lidarr.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/NzbDrone.Common/Http/Dispatchers/ManagedHttpDispatcher.cs \
        --replace-fail 'useIPv6 = !routableIPv4;' 'useIPv6 = true;'
    '';
  });
}
