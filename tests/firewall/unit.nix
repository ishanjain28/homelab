{ lib }:
let
  addr = import ../../lib/firewall/address.nix { inherit lib; };
  fixture = import ./fixture.nix { inherit lib; };
  inherit (fixture) compile args;
  succeeds = x: (builtins.tryEval (builtins.deepSeq x true)).success;
  rejects = x: !(succeeds x);
  multi = args // {
    inventory = args.inventory // {
      networks = args.inventory.networks // {
        "99" = {
          ipv4Prefix = "10.99.0.0/24";
          ipv6Prefix = "fd42:99::/64";
        };
      };
    };
    ipv4 = args.ipv4 // {
      a = args.ipv4.a // {
        "99" = "10.99.0.2";
      };
    };
    services = args.services // {
      "test/a" = args.services."test/a" // {
        attachments = args.services."test/a".attachments // {
          "99" = {
            interface = "pa99";
            mac = "02:00:00:00:99:02";
            network = "99";
          };
        };
        networkPolicy = {
          mode = "enforce";
          egress = [
            {
              via = "50";
              to.service = "b";
              endpoint = "web";
            }
          ];
        };
      };
      "test/b" = args.services."test/b" // {
        networkPolicy = {
          mode = "enforce";
          ingress.web.from = [
            {
              service = "a";
              attachment = "50";
            }
          ];
        };
      };
    };
  };
  tests = {
    eui64 = addr.fromMac "2a0a:6040:4004:50::/64" "02:97:bc:80:c9:02" == "2a0a:6040:4004:50:97:bcff:fe80:c902";
    universalBit = addr.fromMac "fd00::/64" "00:11:22:33:44:55" == "fd00:0:0:0:211:22ff:fe33:4455";
    compressed = addr.fromMac "::/64" "02:00:00:00:00:01" == "0:0:0:0:0:ff:fe00:1";
    invalidPrefix = rejects (addr.fromMac "fd00::/48" "02:00:00:00:00:01");
    hostBits = rejects (addr.fromMac "fd00::1/64" "02:00:00:00:00:01");
    malformed = rejects (addr.ipv6 "fd00:::1");
    subnet = addr.contains4 "10.50.0.0/24" "10.50.0.2" && !(addr.contains4 "10.50.0.0/24" "10.50.1.2");
    zeroPrefix = addr.contains4 "0.0.0.0/0" "255.255.255.255";
    valid = succeeds fixture.compiled;
    missingAddress = rejects (compile (args // { ipv4 = { }; }));
    outsideSubnet = rejects (
      compile (
        args
        // {
          ipv4 = args.ipv4 // {
            a."50" = "10.51.0.2";
          };
        }
      )
    );
    duplicateAddress = rejects (
      compile (
        args
        // {
          ipv4 = args.ipv4 // {
            a."50" = "10.50.0.3";
          };
        }
      )
    );
    missingEndpoint = rejects (
      compile (
        args
        // {
          services = args.services // {
            "test/a" = args.services."test/a" // {
              networkPolicy = {
                mode = "enforce";
                egress = [
                  {
                    to.service = "b";
                    endpoint = "missing";
                  }
                ];
              };
            };
          };
        }
      )
    );
    noImplicitPorts = rejects (
      compile (
        args
        // {
          services = args.services // {
            "test/a" = args.services."test/a" // {
              networkPolicy = {
                mode = "enforce";
                egress = [ { to.host = "router"; } ];
              };
            };
          };
        }
      )
    );
    multiAttachment = succeeds (compile multi);
    noAttachmentUnion = lib.all (r: r.egress == [ ] && r.ingress == [ ]) (
      builtins.filter (r: r.identity.attachment == "99") (compile multi).report
    );
    ambiguousAttachment = rejects (
      compile (
        multi
        // {
          services = multi.services // {
            "test/a" = multi.services."test/a" // {
              networkPolicy = {
                mode = "enforce";
                egress = [
                  {
                    to.service = "b";
                    endpoint = "web";
                  }
                ];
              };
            };
          };
        }
      )
    );
    renumbering =
      let
        changed = compile (
          args
          // {
            inventory = args.inventory // {
              networks."50" = args.inventory.networks."50" // {
                ipv6Prefix = "2001:db8:abcd::/64";
              };
            };
          }
        );
      in
      lib.all (r: lib.all (ip: lib.hasPrefix "2001:db8:abcd:" ip) r.identity.v6) changed.report;
    profileOrigin = lib.any (r: lib.any (grant: grant.origin == "infrastructure:dns") r.egress) fixture.compiled.report;
    noStateBypass = !(lib.hasInfix "ct state established,related accept" fixture.compiled.contents);
  };
in
assert lib.all (x: x) (builtins.attrValues tests);
tests
