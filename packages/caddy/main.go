package main

import (
	_ "github.com/caddy-dns/cloudflare"
	caddycmd "github.com/caddyserver/caddy/v2/cmd"
	_ "github.com/caddyserver/caddy/v2/modules/standard"
	_ "github.com/zhangjiayin/caddy-geoip2"
)

func main() {
	caddycmd.Main()
}
