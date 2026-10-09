_inputs: _final: prev: { grafana-alloy = prev.grafana-alloy.override { systemdLibs = prev.systemd; }; }
