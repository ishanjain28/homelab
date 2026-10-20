#!/usr/bin/env bash

: "${PIA_REGION:?}" "${PIA_USER:?}" "${PIA_PASS:?}" "${PIA_CA:?}" "${RUNTIME_DIRECTORY:?}"

WG_INTERFACE=wg0
WG_TABLE=51820
PING_TARGET=1.1.1.1
PING_FAILURES=3
BIND_INTERVAL=900
port_file="$RUNTIME_DIRECTORY/env"

fail() { echo "ERROR: $*" >&2; exit 1; }

teardown() {
  rm -f "$port_file"
  ip -4 rule del not fwmark "$WG_TABLE" table "$WG_TABLE" 2>/dev/null || true
  ip -4 rule del table main suppress_prefixlength 0 2>/dev/null || true
  ip link del "$WG_INTERFACE" 2>/dev/null || true
}
trap teardown EXIT
teardown

# Calls a PIA server API through its pinned CA and returns the JSON only if PIA reports status OK.
pia_api() {
  local host="$1" ip="$2" port="$3" path="$4"
  shift 4
  curl -sS --fail --max-time 15 -G --connect-to "$host::$ip:" --cacert "$PIA_CA" "$@" "https://$host:$port/$path" |
    jq -e 'select(.status == "OK")'
}

tunnel_ok() { ping -c 1 -w "${1:-5}" -I "$WG_INTERFACE" "$PING_TARGET" >/dev/null 2>&1; }

echo "requesting PIA token"
token=$(curl -sS --fail --max-time 20 --form "username=$PIA_USER" --form "password=$PIA_PASS" \
  https://www.privateinternetaccess.com/api/client/v2/token | jq -er .token) || fail "token request failed"

echo "selecting WireGuard server in region '$PIA_REGION'"
IFS=$'\t' read -r wg_host wg_ip < <(curl -sS --fail --max-time 20 https://serverlist.piaservers.net/vpninfo/servers/v6 |
  head -n 1 | jq -er --arg region "$PIA_REGION" \
  '.regions[] | select(.id == $region and .port_forward) | [.servers.wg[0].cn, .servers.wg[0].ip] | @tsv') ||
  fail "no port-forwarding WireGuard server in region '$PIA_REGION'"

private_key=$(wg genkey)
public_key=$(wg pubkey <<<"$private_key")

echo "registering key with $wg_host ($wg_ip)"
IFS=$'\t' read -r server_key server_port server_ip gateway peer_ip < <(
  pia_api "$wg_host" "$wg_ip" 1337 addKey --data-urlencode "pt=$token" --data-urlencode "pubkey=$public_key" |
    jq -er '[.server_key, .server_port, .server_ip, .server_vip, .peer_ip] | @tsv'
) || fail "addKey failed"

echo "bringing up $WG_INTERFACE ($peer_ip -> $server_ip:$server_port)"
ip link add "$WG_INTERFACE" type wireguard
wg set "$WG_INTERFACE" private-key <(echo "$private_key") fwmark "$WG_TABLE" \
  peer "$server_key" endpoint "$server_ip:$server_port" allowed-ips 0.0.0.0/0 persistent-keepalive 25
ip -4 address add "$peer_ip/32" dev "$WG_INTERFACE"
ip link set "$WG_INTERFACE" mtu 1420 up
ip -4 route add default dev "$WG_INTERFACE" table "$WG_TABLE"
ip -4 rule add not fwmark "$WG_TABLE" table "$WG_TABLE"
ip -4 rule add table main suppress_prefixlength 0
tunnel_ok 30 || fail "tunnel to $wg_host never answered pings"

echo "requesting forwarded port"
IFS=$'\t' read -r payload sig < <(pia_api "$wg_host" "$gateway" 19999 getSignature --data-urlencode "token=$token" |
  jq -er '[.payload, .signature] | @tsv') || fail "getSignature failed"
port=$(base64 -d <<<"$payload" | jq -er .port)
bind_port() {
  pia_api "$wg_host" "$gateway" 19999 bindPort --data-urlencode "payload=$payload" --data-urlencode "signature=$sig" >/dev/null
}
bind_port || fail "bindPort failed"
(umask 022 && echo "PIA_PORT=$port" >"$port_file")
echo "$WG_INTERFACE up via $wg_host, forwarded port $port"

failures=0
next_bind=$((SECONDS + BIND_INTERVAL))
while sleep 60; do
  if tunnel_ok; then
    failures=0
  else
    failures=$((failures + 1))
    echo "ping to $PING_TARGET failed ($failures/$PING_FAILURES)"
    [ "$failures" -lt "$PING_FAILURES" ] || fail "tunnel stopped responding"
  fi
  if [ "$SECONDS" -ge "$next_bind" ]; then
    bind_port || fail "bindPort refresh failed"
    next_bind=$((SECONDS + BIND_INTERVAL))
  fi
done
