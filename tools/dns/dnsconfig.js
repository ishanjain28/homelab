var config = require(dns);

var REG_NONE = NewRegistrar("none");
var REG_PORKBUN = NewRegistrar("porkbun");
var DSP_CLOUDFLARE = NewDnsProvider("cloudflare");
var DSP_CLOUDFLARE_REDIRECTS = NewDnsProvider("cloudflare-redirects", {
  manage_single_redirects: true,
});
var DSP_ADGUARDHOME_HOME = NewDnsProvider("adguardhome.home");
var DSP_ADGUARDHOME_DEL = NewDnsProvider("adguardhome.del");

DEFAULTS(CF_PROXY_DEFAULT_OFF, DefaultTTL("1"));

function address(name) {
  if (!config.addresses[name]) {
    throw "unknown address '" + name + "'";
  }
  return config.addresses[name];
}

function addressRecords(label, entry) {
  var v4 = entry.v4 || [];
  var v6 = entry.v6 || [];
  var via = entry.via || [];

  for (var i = 0; i < via.length; i++) {
    v4 = v4.concat(address(via[i]).v4);
    v6 = v6.concat(address(via[i]).v6);
  }

  var records = [];
  for (var i = 0; i < v4.length; i++) {
    records.push(A(label, v4[i]));
  }
  for (var i = 0; i < v6.length; i++) {
    records.push(AAAA(label, v6[i]));
  }
  return records;
}

function serviceRecords(view, domain) {
  var records = [];

  for (var service in config.services) {
    var entry = config.services[service][view];
    if (!entry) {
      continue;
    }

    var labels = entry[domain] || [];
    for (var i = 0; i < labels.length; i++) {
      records = records.concat(addressRecords(labels[i], entry));
    }
  }

  return records;
}

function directRecords() {
  var records = [];

  for (var service in config.services) {
    var direct = config.services[service].direct || {};
    for (var site in direct) {
      records = records.concat(addressRecords(service + "." + site + ".direct", direct[site]));
    }
  }

  return records;
}

require("./ishanjain.me.js");
require("./ishanjain.in.js");
require("./vax.ovh.js");
