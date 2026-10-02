{ lib }:
let
  fixture = import ./fixture.nix { inherit lib; };
  inherit (fixture) args compile;
  render = compiled: "table bridge homelab_services {\n${compiled.contents}\n}\n";
  deny = args // {
    services = args.services // {
      "test/b" = args.services."test/b" // {
        networkPolicy = {
          mode = "enforce";
        };
      };
    };
  };
in
{
  allow = render (compile args);
  revoke = render (compile deny);
  audit = render (
    compile (
      deny
      // {
        services = lib.mapAttrs (
          _: s:
          s
          // {
            networkPolicy = s.networkPolicy // {
              mode = if s.networkPolicy.mode == "off" then "off" else "audit";
            };
          }
        ) deny.services;
      }
    )
  );
}
