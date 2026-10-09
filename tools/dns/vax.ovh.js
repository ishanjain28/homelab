D("vax.ovh!public", REG_NONE, DnsProvider(DSP_CLOUDFLARE_REDIRECTS),
  NAMESERVER("mario.ns.cloudflare.com."),
  NAMESERVER("tegan.ns.cloudflare.com."),

  // HTTPS record updates are done by Caddy for ECH
  IGNORE("*", "HTTPS"),

  TXT("@", "v=spf1 -all"),
  TXT("@", "v=DKIM1; p="),
  TXT("@", "v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s;"),

  addressRecords("*", { via: ["caddy-delhi"] }),

  A("@", "192.0.2.1", CF_PROXY_ON),

  CF_TEMP_REDIRECT("vax.ovh/*", "https://ishanjain.me/$1"),

  serviceRecords("public", "vax.ovh")
);

D("vax.ovh!home", REG_NONE, DnsProvider(DSP_ADGUARDHOME_HOME),
  ADGUARDHOME_A_PASSTHROUGH("del.dns", ""),
  ADGUARDHOME_AAAA_PASSTHROUGH("del.dns", ""),

  serviceRecords("home", "vax.ovh")
);
