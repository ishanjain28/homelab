{
  inputs,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.${namespace};
let
  inherit (inputs) self;

  keys = {
    annapurna = "age1yzg8yagn35ltasll84ghskth9jz9ve2lar43hvk438z9velxl5jsunzt08";
    # Used only in CI and the only key that can read DNS credentials
    ci_dns = "age1zj74mu46knf8zgp6fjtcy6um2w3lfxg4lyjkzkhz7c5jgj3e9uzsevusp4";

    # /* The primary keys saved on yubikeys that can be used to decrypt _anything_.
    homelab_p1 = "age1yubikey1q0kyddtpx2j980tggcjn8dnxjvn046zvaygfzfryc5cy560wwmnxwhzd7sj";
    homelab_p2 = "age1yubikey1q0znr9l27dq3wfu3ep2hhzujtjyfy2v86l2jew3murewkt6c4ajactg724a";
    homelab_p3 = "age1yubikey1q2qs6sm4gghdr6qcfmgf4c0cct25p9mn5p9d3vejl4w0sgul0luzgkskpz7";

    kamet = "age1kyujec5hpyzrr4ld5ckxpma0evu2thjx2jkqjfycy3r38xfkgu3sz8u6kw";
    kanchenjunga = "age1cvepfy7dpd408h7wn4thm23wzlwu3km67fzp3et2e3rrvurwjfsq60uf6r";
    manaslu = "age1xrr2y03ph2el9fwnvgngqujhf4kpcra3znlrcn90wte9nkea23wssqhzq7";

    # macbook key used to decrypt gitconfig and related files in future.
    # Only used in the one home-manager profile.
    "ishan@work-macbook" = "age1s45dwj5ger9hrnta0rguvcetkc5zjws4zac9g89g2jwvvuttmfgs2dudue";
  };

  machines = intersectAttrs keys (self.nixosConfigurations // self.homeConfigurations);

  files =
    machine:
    map (file: removePrefix "./" (path.removePrefix (repoFile "") file)) (
      catAttrs "sopsFile" (attrValues machine.config.sops.secrets)
    );

  recipients = zipAttrs (mapAttrsToList (name: machine: genAttrs (files machine) (_: name)) machines) // {
    "secrets/dns/records.json" = attrNames self.nixosConfigurations ++ [
      "ci_dns"
      "ishan@work-macbook"
    ];
    "secrets/dns/creds.json" = [ "ci_dns" ];
  };

  rule = path_regex: names: {
    inherit path_regex;
    key_groups = [
      {
        age = map (name: keys.${name}) (
          [
            "homelab_p1"
            "homelab_p2"
            "homelab_p3"
          ]
          ++ names
        );
      }
    ];
  };

  sopsConfig = (pkgs.formats.yaml { }).generate "sops.yaml" {
    creation_rules = mapAttrsToList (file: rule "^${escapeRegex file}$") recipients ++ [
      # special attention required for postgresql conf files since they are partially encrypted.
      # unencrypted portion is read by the bootstrapping/configuration SQL in postgresql module.
      (rule "^secrets/postgresql/" [ ] // { encrypted_regex = "^(users)$"; })
      (rule ".*" [ ])
    ];
  };
in
pkgs.writeShellApplication {
  name = "sops-sync";
  runtimeInputs = with pkgs; [
    age-plugin-yubikey
    coreutils
    findutils
    git
    sops
  ];
  text = ''
    cd "$(git rev-parse --show-toplevel)"
    install -m 644 ${sopsConfig} .sops.yaml
    find secrets -type f -exec sops updatekeys -y {} \;
  '';
}
