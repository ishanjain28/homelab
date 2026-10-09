var delhi = address("caddy-delhi");

D("ishanjain.me!public", REG_PORKBUN, DnsProvider(DSP_CLOUDFLARE),
  NAMESERVER("mario.ns.cloudflare.com."),
  NAMESERVER("tegan.ns.cloudflare.com."),

  // HTTPS record updates are done by Caddy for ECH
  IGNORE("*", "HTTPS"),

  IGNORE("@", "A"),
  IGNORE("@", "AAAA"),

  CNAME("fm1._domainkey", "fm1.ishanjain.me.dkim.fmhosted.com."),
  CNAME("fm2._domainkey", "fm2.ishanjain.me.dkim.fmhosted.com."),
  CNAME("fm3._domainkey", "fm3.ishanjain.me.dkim.fmhosted.com."),
  CNAME("home", "heh08sga445.sn.mynetname.net."),
  CNAME("mesmtp._domainkey", "mesmtp.ishanjain.me.dkim.fmhosted.com."),
  CNAME("www", "@", CF_PROXY_ON),

  MX("@", 10, "in1-smtp.messagingengine.com.", TTL("1h")),
  MX("@", 20, "in2-smtp.messagingengine.com.", TTL("1h")),

  TXT("@", "google-site-verification=X_no9RSVWSYBGpZ55dwUXB4cehJYYGLRCWHv7WoXbQ8"),
  TXT("@", "v=spf1 include:spf.messagingengine.com -all"),
  TXT("_atproto", "did=did:plc:injz2aaiflg5mho3mqqoqujr"),
  TXT("_discord", "dh=8d45b2a248fb5c4045912c8ffa8f8cd158e252e2"),
  TXT("_dmarc", "v=DMARC1; p=quarantine; rua=mailto:d20a42b634154a888ad7eb473efc9f39@dmarc-reports.cloudflare.net,mailto:contact@ishanjain.me"),
  TXT("hibp-verify", "dweb_kpwnpur2gudb1eco3r6nkicm"),

  SRV("_autodiscover._tcp", 0, 1, 443, "autodiscover.fastmail.com."),
  SRV("_caldav._tcp", 0, 0, 0, "."),
  SRV("_caldavs._tcp", 0, 1, 443, "caldav.fastmail.com."),
  SRV("_carddav._tcp", 0, 0, 0, "."),
  SRV("_carddavs._tcp", 0, 1, 443, "carddav.fastmail.com."),
  SRV("_imap._tcp", 0, 0, 0, "."),
  SRV("_imaps._tcp", 0, 1, 993, "imap.fastmail.com."),
  SRV("_jmap._tcp", 0, 1, 443, "api.fastmail.com."),
  SRV("_pop3._tcp", 0, 0, 0, "."),
  SRV("_pop3s._tcp", 10, 1, 995, "pop.fastmail.com."),
  SRV("_submission._tcp", 0, 0, 0, "."),
  SRV("_submissions._tcp", 0, 1, 465, "smtp.fastmail.com."),

  A("4", delhi.v4[0]),
  AAAA("6", delhi.v6[0]),
  addressRecords("a", { via: ["caddy-delhi"] }),
  A("del.irc", delhi.v4[0]),

  addressRecords("ech", { via: ["caddy-delhi"] }),

  serviceRecords("public", "ishanjain.me")
);

// DNS overrides when at home
D("ishanjain.me!home", REG_NONE, DnsProvider(DSP_ADGUARDHOME_HOME),
  addressRecords("home", { via: ["caddy-home"] }),

  serviceRecords("home", "ishanjain.me"),
  directRecords()
);

// Direct address mapping at AGH Delhi
D("ishanjain.me!del", REG_NONE, DnsProvider(DSP_ADGUARDHOME_DEL),
  directRecords()
);
