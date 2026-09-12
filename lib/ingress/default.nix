{ lib, ... }:
let
  inherit (lib)
    concatLists
    concatMap
    concatMapStringsSep
    filter
    foldl'
    hasAttr
    mapAttrsToList
    optional
    optionalAttrs
    recursiveUpdate
    sort
    unique
    ;

  genMatch = matcher: optionalAttrs (matcher != { }) { match = [ matcher ]; };

  routeMatcher = route: route.matcher // optionalAttrs (route.paths != [ ]) { path = route.paths; };

  genReverseProxy =
    route:
    route.reverseProxy
    // {
      handler = "reverse_proxy";
      upstreams = map (dial: { inherit dial; }) route.upstreams;
    };

  genHandles =
    entry: route:
    let
      handles = route.handlers ++ optional (route.upstreams != [ ]) (genReverseProxy route);
    in
    if handles == [ ] then
      throw "Ingress route for service '${entry.serviceName}' has no handlers or upstreams."
    else
      handles;

  genLeafRoute =
    entry:
    genMatch (routeMatcher entry.route)
    // {
      handle = genHandles entry entry.route;
    }
    // optionalAttrs (entry.route ? terminal && entry.route.terminal != null) {
      inherit (entry.route) terminal;
    };

  leafHasMatcher = route: route.paths != [ ] || route.matcher != { };

  routeBefore =
    left: right:
    if left.route.order != right.route.order then
      left.route.order > right.route.order
    else
      left.serviceName < right.serviceName;

  expandEntry =
    entry:
    if entry.route.routes == [ ] then
      [
        {
          inherit (entry) serviceName;
          route = {
            paths = [ ];
            matcher = { };
            inherit (entry.route) handlers upstreams reverseProxy;
            terminal = null;
          };
        }
      ]
    else
      map (route: {
        inherit (entry) serviceName;
        inherit route;
      }) entry.route.routes;

  matcherSignature = route: builtins.toJSON (genMatch (routeMatcher route));

  duplicateValues =
    values:
    unique (filter (value: builtins.length (filter (candidate: candidate == value) values) > 1) values);

  domainErrors =
    domain: entries:
    let
      leafEntries = concatMap expandEntry entries;
      fallbackServices = map (entry: entry.serviceName) (
        filter (entry: !(leafHasMatcher entry.route)) leafEntries
      );
      matcherEntries = filter (entry: leafHasMatcher entry.route) leafEntries;
      duplicateMatchers = duplicateValues (map (entry: matcherSignature entry.route) matcherEntries);
    in
    optional (builtins.length fallbackServices > 1)
      "domain '${domain}' has multiple fallback routes from: ${
        concatMapStringsSep ", " (name: name) fallbackServices
      }"
    ++ map (signature: "domain '${domain}' has duplicate matcher ${signature}") duplicateMatchers;

  entryErrors =
    entry:
    let
      inherit (entry) route;
      hasTopLevelHandles = route.handlers != [ ] || route.upstreams != [ ] || route.reverseProxy != { };
      leafRoutes = if route.routes == [ ] then [ route ] else route.routes;
      emptyLeafRoutes = filter (leaf: leaf.handlers == [ ] && leaf.upstreams == [ ]) leafRoutes;
      proxyWithoutUpstreams = filter (leaf: leaf.reverseProxy != { } && leaf.upstreams == [ ]) leafRoutes;
    in
    optional (
      route.routes != [ ] && hasTopLevelHandles
    ) "service '${entry.serviceName}' mixes subroutes with top-level handlers or proxy settings"
    ++ optional (
      emptyLeafRoutes != [ ]
    ) "service '${entry.serviceName}' contains a route with no handlers or upstreams"
    ++ optional (
      proxyWithoutUpstreams != [ ]
    ) "service '${entry.serviceName}' configures reverseProxy without any upstreams";

  collectRoutes =
    ingressName: services:
    concatLists (
      mapAttrsToList (
        serviceName: service:
        if service.enable && service ? ingress && hasAttr ingressName service.ingress then
          [
            {
              inherit serviceName;
              route = service.ingress.${ingressName};
            }
          ]
        else
          [ ]
      ) services
    );

  groupRoutesByDomain =
    entries:
    foldl' (
      grouped: domain:
      grouped
      // {
        ${domain} = filter (entry: builtins.elem domain entry.route.domains) entries;
      }
    ) { } (unique (concatMap (entry: entry.route.domains) entries));

  genDomainRoute =
    domain: entries:
    let
      sortedEntries = sort routeBefore entries;
      entry = builtins.head sortedEntries;
      direct = builtins.length sortedEntries == 1 && entry.route.routes == [ ];
      handle =
        if direct then
          genHandles entry entry.route
        else
          [
            {
              handler = "subroute";
              routes = map genLeafRoute (concatMap expandEntry sortedEntries);
            }
          ];
    in
    genMatch { host = [ domain ]; }
    // {
      inherit handle;
      terminal = true;
    };
in
{
  mkIngressConfig =
    {
      ingressName,
      caddy,
      services,
    }:
    let
      entries = collectRoutes ingressName services;
      grouped = groupRoutesByDomain entries;
      errors = concatMap entryErrors entries ++ concatLists (mapAttrsToList domainErrors grouped);
      generatedRoutes = mapAttrsToList genDomainRoute grouped;
      existingServer = caddy.settings.apps.http.servers.${caddy.server.name} or { };
      generatedServer = recursiveUpdate existingServer (
        recursiveUpdate caddy.server.settings {
          inherit (caddy.server) listen;
          named_routes = caddy.server.namedRoutes;
          routes = caddy.server.routes.before ++ generatedRoutes ++ caddy.server.routes.after;
        }
      );
      generatedConfig = recursiveUpdate caddy.settings {
        apps.http.servers.${caddy.server.name} = generatedServer;
      };
    in
    if errors == [ ] then
      generatedConfig
    else
      throw "Invalid routes for ingress '${ingressName}': ${
        concatMapStringsSep "; " (error: error) errors
      }";
}
