D("ishanjain.in!public", REG_PORKBUN, DnsProvider(DSP_CLOUDFLARE_REDIRECTS),
  NAMESERVER("mario.ns.cloudflare.com."),
  NAMESERVER("tegan.ns.cloudflare.com."),

  // HTTPS record updates are done by Caddy for ECH
  IGNORE("*", "HTTPS"),

  // DS("@", 2371, 13, 2, "14E6B9C3F3B6755DC2EFA6AC59C178A999E19455A2E9C723E67C185C0ABFE458"),

  CNAME("mesmtp._domainkey", "mesmtp.ishanjain.me.dkim.fmhosted.com."),
  CNAME("fm1._domainkey", "fm1.ishanjain.me.dkim.fmhosted.com."),
  CNAME("fm2._domainkey", "fm2.ishanjain.me.dkim.fmhosted.com."),
  CNAME("fm3._domainkey", "fm3.ishanjain.me.dkim.fmhosted.com."),

  MX("@", 10, "in1-smtp.messagingengine.com.", TTL("1h")),
  MX("@", 20, "in2-smtp.messagingengine.com.", TTL("1h")),

  TXT("@", "v=spf1 include:spf.messagingengine.com -all"),

  SRV("_submission._tcp", 0, 0, 0, "."),
  SRV("_imap._tcp", 0, 0, 0, "."),
  SRV("_pop3._tcp", 0, 0, 0, "."),
  SRV("_submissions._tcp", 0, 1, 465, "smtp.fastmail.com."),
  SRV("_imaps._tcp", 0, 1, 993, "imap.fastmail.com."),
  SRV("_pop3s._tcp", 10, 1, 995, "pop.fastmail.com."),
  SRV("_jmap._tcp", 0, 1, 443, "api.fastmail.com."),
  SRV("_autodiscover._tcp", 0, 1, 443, "autodiscover.fastmail.com."),
  SRV("_carddav._tcp", 0, 0, 0, "."),
  SRV("_carddavs._tcp", 0, 1, 443, "carddav.fastmail.com."),
  SRV("_caldav._tcp", 0, 0, 0, "."),
  SRV("_caldavs._tcp", 0, 1, 443, "caldav.fastmail.com."),

  A("@", "192.0.2.1", CF_PROXY_ON),

  CF_TEMP_REDIRECT("ishanjain.in/*", "https://ishanjain.me/$1"),
);
