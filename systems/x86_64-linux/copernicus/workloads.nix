{ lib, namespace }:
with lib.${namespace};
{
  karakeep = enabled // {
    vlans = [ 50 ];
    runtimeId = 30348;
    volumes = [
      "karakeep"
      "karakeep-meilisearch"
    ];
    ingress.home = {
      domains = [ "link.ishanjain.me" ];
      upstreams = [ "10.0.50.33:3000" ];
    };
  };

  omada = enabled // {
    vlans = [ 99 ];
    runtimeId = 30349;
    volumes = [ "omada" ];
    ingress.home = {
      domains = [ "omada.home.ishanjain.me" ];
      routes = [
        {
          matcher.not = [
            {
              header = {
                Omada-Request-Source = [ "app-local" ];
                User-Agent = [ "Omada Android" ];
              };
            }
          ];
          handlers = [
            {
              handler = "invoke";
              name = "authelia-integration";
            }
          ];
        }
        {
          upstreams = [ "10.0.99.16:8043" ];
          reverseProxy.transport = {
            protocol = "http";
            tls = {
              insecure_skip_verify = true;
              server_name = "omada";
            };
          };
        }
      ];
    };
  };

  prowlarr = enabled // {
    vlans = [ 50 ];
    runtimeId = 30350;
  };

  nitter = enabled // {
    vlans = [ 50 ];
    runtimeId = 30351;
    ingress.home = {
      domains = [
        "t.ishanjain.me"
        "t.vax.ovh"
      ];
      routes = [
        {
          paths = [ "/.*" ];
          handlers = [
            {
              handler = "invoke";
              name = "authelia-integration";
            }
          ];
        }
        {
          upstreams = [ "10.0.50.32:8080" ];
          reverseProxy.transport.protocol = "http";
        }
      ];
    };
  };

  caddy = enabled // {
    vlans = [ 50 ];
    runtimeId = 30352;
    ingressProvider.name = "home";
    server.namedRoutes = {
      authelia-integration = {
        handle = [
          {
            handler = "reverse_proxy";
            upstreams = [ { dial = "10.0.50.17:9091"; } ];
            rewrite = {
              method = "GET";
              uri = "/api/authz/forward-auth";
            };
            headers.request.set = {
              X-Forwarded-Method = [ "{http.request.method}" ];
              X-Forwarded-Uri = [ "{http.request.uri}" ];
            };
            handle_response = [
              {
                match.status_code = [ 5 ];
                routes = [
                  {
                    handle = [
                      {
                        handler = "static_response";
                        body = "Authenticator down";
                        status_code = "{rp.status_code}";
                      }
                    ];
                  }
                ];
              }
              {
                match.status_code = [ 403 ];
                routes = [
                  {
                    handle = [
                      {
                        handler = "static_response";
                        body = "Authenticator says user is not allowed access to this application. Contact Ishan";
                        status_code = "403";
                      }
                    ];
                  }
                ];
              }
              {
                match.status_code = [ 2 ];
                routes = [
                  {
                    handle = [
                      { handler = "vars"; }
                      {
                        handler = "headers";
                        request.set = {
                          Remote-Email = [ "{http.reverse_proxy.header.Remote-Email}" ];
                          Remote-Name = [ "{http.reverse_proxy.header.Remote-Name}" ];
                          Remote-User = [ "{http.reverse_proxy.header.Remote-User}" ];
                        };
                      }
                    ];
                  }
                ];
              }
            ];
          }
        ];
        match = [
          {
            not = [
              { path = [ "/.well-known/acme-challenge*" ]; }
            ];
          }
        ];
        terminal = false;
      };

      authelia-logout = {
        handle = [
          {
            handler = "reverse_proxy";
            upstreams = [ { dial = "10.0.50.17:9091"; } ];
            rewrite = {
              method = "POST";
              uri = "/api/logout";
            };
            handle_response = [
              {
                match.status_code = [ 5 ];
                routes = [
                  {
                    handle = [
                      {
                        handler = "static_response";
                        body = "Authenticator down";
                        status_code = "{rp.status_code}";
                      }
                    ];
                  }
                ];
              }
              {
                match.status_code = [ 2 ];
                routes = [
                  {
                    handle = [ { handler = "vars"; } ];
                  }
                ];
              }
            ];
          }
        ];
        match = [
          {
            not = [
              { path = [ "/.well-known/acme-challenge*" ]; }
            ];
          }
        ];
        terminal = false;
      };
    };
  };
}
