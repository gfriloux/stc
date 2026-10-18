# Relic: docker-traefik
#
# Runs Traefik v3 in a Docker container as a reverse proxy.
# Auto-generates the static config from Nix options.
# The dynamic config (routes, middlewares) is supplied at runtime via dynamicConfigFile.
#
# This is the container deployment. STC also ships a native Traefik
# (`relics-traefik`, services.traefik) for non-Docker hosts. They are separate —
# pick one per host. This one uses the TLS-ALPN-01 challenge (`tlsChallenge`)
# rather than the native's HTTP-01, but both name their resolver `letsencrypt`.
#
# When stc.relics.docker.crowdsec.enable = true, the CrowdSec bouncer plugin is
# automatically wired into the static config and traefik waits for crowdsec.
#
# Secrets: point stc.relics.docker.traefik.dynamicConfigFile at whatever your
# secrets provider materialises.
#
# Container labels referencing a certresolver or a middleware are validated at
# evaluation time — see the "reference validation" block below for why that is
# this relic's job and where its knowledge stops.
{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.stc.relics.docker.traefik;
  dockerLib = import ./_lib.nix;

  # Guarded on the option existing so this relic stays usable on its own:
  # the crowdsec relic declares stc.relics.docker.crowdsec only when imported.
  crowdsecEnabled =
    (options.stc.relics.docker ? crowdsec) && config.stc.relics.docker.crowdsec.enable;

  # When the socket-proxy relic is enabled, Traefik talks to the Docker API over
  # TCP through the filtering proxy instead of bind-mounting the raw socket.
  # Guarded on the option existing so this relic stays usable on its own.
  socketProxyEnabled =
    (options.stc.relics.docker ? socketProxy) && config.stc.relics.docker.socketProxy.enable;
  socketProxyNetwork = config.stc.relics.docker.socketProxy.network;
  # Inserted raw after the heredoc strips its common indent, so this carries the
  # already-stripped (4-space) indentation to sit under the docker provider.
  dockerProviderEndpoint = lib.optionalString socketProxyEnabled "\n    endpoint: \"tcp://docker-socket-proxy:2375\"";

  crowdsecPlugin = lib.optionalString crowdsecEnabled ''

    experimental:
      plugins:
        bouncer:
          moduleName: "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
          version: "v1.5.1"
  '';

  staticConfig = pkgs.writeText "traefik.yml" ''
    entryPoints:
      web:
        address: ":80"
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https

      websecure:
        address: ":443"
        transport:
          respondingTimeouts:
            readTimeout: 600s
            idleTimeout: 600s

      traefik:
        address: "127.0.0.1:8080"

    api:
      dashboard: ${lib.boolToString cfg.enableDashboard}

    ping:
      entryPoint: traefik

    accessLog:
      filePath: "/logs/traefik.log"
      format: json
      fields:
        headers:
          defaultMode: drop
          names:
            User-Agent: keep
            X-Real-Ip: keep
            X-Forwarded-For: keep
            X-Forwarded-Proto: keep

    certificatesResolvers:
      letsencrypt:
        acme:
          email: "${cfg.acme.email}"
          storage: "acme.json"
          tlsChallenge: {}

    providers:
      docker:
        watch: true
        network: web${dockerProviderEndpoint}
      file:
        filename: "/etc/traefik/traefik_dynamic.yml"
    ${crowdsecPlugin}
  '';

  # ── Reference validation ───────────────────────────────────────────────────
  #
  # Traefik's dynamic configuration is assembled from container labels, and a
  # label referencing something non-existent is an error NOWHERE in the chain:
  # it evaluates, it builds, it deploys, and the router comes up with the
  # referenced feature simply missing. An unknown certresolver yields Traefik's
  # default self-signed certificate; an unknown middleware yields a route
  # *without* that protection — and when the missing one is the CrowdSec
  # bouncer, the result is an unprotected public route that reads as protected
  # in the configuration.
  #
  # STC owns the producing side, so it knows the valid names and the consumer
  # only knows what it typed. Checking here costs one evaluation pass and turns
  # a silent exposure into a build failure.
  containers = config.virtualisation.oci-containers.containers;

  # The static config above declares its resolvers in full, with no consumer
  # escape hatch, so this singleton is the valid set — known for certain, which
  # is what makes a hard assertion fair here.
  validCertResolvers = ["letsencrypt"];

  # Middlewares declared by labels belong to the docker provider, and STC sees
  # every one of them: traefik.http.middlewares.<name>.<type>.<field>.
  dockerMiddlewares = lib.unique (
    lib.concatMap (
      c:
        lib.concatMap (
          label: let
            parts = lib.splitString "." label;
          in
            lib.optional
            (lib.length parts >= 4 && lib.take 3 parts == ["traefik" "http" "middlewares"])
            (lib.elemAt parts 3)
        )
        (lib.attrNames (c.labels or {}))
    )
    (lib.attrValues containers)
  );

  # The @file suffix is optional in fileMiddlewares: "crowdsec" and
  # "crowdsec@file" must name the same thing, since a consumer will paste
  # whichever form its labels already use.
  bareName = value: lib.head (lib.splitString "@" value);
  fileMiddlewareNames = map bareName cfg.fileMiddlewares;

  # Traefik's own resolution rule: an unqualified reference resolves within the
  # provider that defined the referencing object, which for a router defined by
  # labels is docker. So a bare name is a docker reference, not a wildcard.
  providerOf = value:
    if lib.hasInfix "@" value
    then lib.last (lib.splitString "@" value)
    else "docker";

  # One record per reference, carrying what an actionable message needs: which
  # container, which router, which value — and which kind, so the two classes
  # keep their own valid set and their own wording.
  references = lib.concatMap (
    container: let
      labels = containers.${container}.labels or {};

      parse = label: let
        parts = lib.splitString "." label;
        router = lib.elemAt parts 3;
        rest = lib.drop 4 parts;
        value = labels.${label};
      in
        if lib.length parts < 5 || lib.take 3 parts != ["traefik" "http" "routers"]
        then []
        else if rest == ["tls" "certresolver"]
        then [
          {
            inherit container router value;
            kind = "certresolver";
          }
        ]
        else if rest == ["middlewares"]
        then
          # A single label holds a comma-separated chain, and each element is an
          # independent reference that can be wrong on its own.
          map (m: {
            inherit container router;
            kind = "middleware";
            value = m;
          })
          (lib.filter (m: m != "") (map lib.trim (lib.splitString "," value)))
        else [];
    in
      lib.concatMap parse (lib.attrNames labels)
  ) (lib.attrNames containers);

  badCertResolvers =
    lib.filter
    (r: r.kind == "certresolver" && !(lib.elem r.value validCertResolvers))
    references;

  middlewareRefs = lib.filter (r: r.kind == "middleware") references;

  badDockerMiddlewares =
    lib.filter
    (r: providerOf r.value == "docker" && !(lib.elem (bareName r.value) dockerMiddlewares))
    middlewareRefs;

  # The file provider's middlewares live in dynamicConfigFile, which STC never
  # reads — it is a consumer secret. So STC cannot know the valid set, and an
  # empty fileMiddlewares is indistinguishable from "not declared yet":
  # asserting against it would fail every consumer using a file middleware,
  # which is most of them. Declaring the list IS the opt-in to this check.
  badFileMiddlewares =
    lib.optionals (cfg.fileMiddlewares != [])
    (
      lib.filter
      (r: providerOf r.value == "file" && !(lib.elem (bareName r.value) fileMiddlewareNames))
      middlewareRefs
    );
  # Any other provider suffix (@kubernetescrd, @consulcatalog, …) is left alone:
  # STC can say nothing about those, and flagging them would be noise.
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "enable"] ["stc" "relics" "docker" "traefik" "enable"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "image"] ["stc" "relics" "docker" "traefik" "image"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "dataDir"] ["stc" "relics" "docker" "traefik" "dataDir"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "acme" "email"] ["stc" "relics" "docker" "traefik" "acme" "email"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "enableDashboard"] ["stc" "relics" "docker" "traefik" "enableDashboard"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "dynamicConfigFile"] ["stc" "relics" "docker" "traefik" "dynamicConfigFile"])
  ];

  options.stc.relics.docker.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy container";

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "traefik:v3.7.6"; # renovate
      description = ''
        Docker image to use for Traefik. Required — STC ships no default so image
        versions live with the consumer, where your own renovate scans the right
        host. Set it in your host config, pinned by tag (and optionally digest):

          stc.relics.docker.traefik.image = "traefik:v3.7.6"; # renovate

        When socketProxy.enable = false this container mounts the raw Docker
        socket, so a silently-swapped image is dangerous — pin it.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/docker/traefik";
      description = "Base directory for Traefik data (logs, acme.json, conf).";
    };

    acme.email = lib.mkOption {
      type = lib.types.str;
      description = "Email address used for Let's Encrypt ACME registration.";
    };

    enableDashboard = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the Traefik API dashboard. Off by default to keep the attack
        surface minimal on production servers.

        Note: the dashboard listens on the in-container `traefik` entrypoint
        (127.0.0.1:8080). That is the container's own loopback, and the port is
        not published, so enabling this alone does not expose it — and an SSH
        tunnel to the host cannot reach it either, since the host loopback is not
        the container's. To reach it, publish the port or add a dynamic-config
        route to the dashboard service.
      '';
    };

    dynamicConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to the Traefik dynamic config file (traefik_dynamic.yml).
        Point this at whatever your secrets provider materialises.
        If null, an empty placeholder is used — add the file manually.
      '';
    };

    fileMiddlewares = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["crowdsec@file" "rate-limit@file" "security-headers@file"];
      description = ''
        The middlewares your Traefik file provider defines — i.e. what lives in
        `dynamicConfigFile`, which STC never reads (it is your secret).

        This is not bureaucracy: it is the declaration that makes validation
        possible. Declaring it turns on eval-time checking of every `@file`
        middleware referenced by a container label, so a typo fails the build
        instead of quietly serving a route *without* that protection. Leave the
        list empty and `@file` references go unchecked — an empty list cannot be
        told apart from "not declared yet", and failing on it would break every
        consumer that uses a file middleware.

        The `@file` suffix is optional here: `"crowdsec"` and `"crowdsec@file"`
        are the same entry.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      [
        {
          assertion = cfg.image != null;
          message = ''
            stc.relics.docker.traefik.enable is true but no image is set.
            STC ships no default image — set it in your host config, e.g.:
              stc.relics.docker.traefik.image = "traefik:v3.7.6"; # renovate
          '';
        }
      ]
      # One assertion per offending reference rather than one per class: a message
      # naming the single container, router and value is actionable, a list of
      # everything wrong at once is not.
      ++ map (r: {
        assertion = false;
        message = ''
          Container "${r.container}": router "${r.router}" references certresolver
          "${r.value}", which stc.relics.docker.traefik does not declare.

          Traefik treats an unresolvable certresolver as no resolver at all: the
          router comes up serving Traefik's default self-signed certificate,
          nothing in the logs reads as a configuration error, and the deploy is
          reported as successful.

          Valid: ${lib.concatStringsSep ", " validCertResolvers}
        '';
      })
      badCertResolvers
      ++ map (r: {
        assertion = false;
        message = ''
          Container "${r.container}": router "${r.router}" references middleware
          "${r.value}", which resolves in the *docker* provider, where no container
          label declares it.

          Traefik drops a middleware it cannot resolve and serves the route
          anyway — so the route runs without that protection. If this one is a
          bouncer, a rate limiter or an auth layer, the route is publicly exposed
          while the configuration says it is not.

          Declared by container labels: ${
            if dockerMiddlewares == []
            then "(none)"
            else lib.concatStringsSep ", " dockerMiddlewares
          }

          An unqualified name resolves in the provider that defined the router,
          which for a label-defined router is docker. If this middleware comes
          from your file provider, write it as "${bareName r.value}@file" and list
          it in stc.relics.docker.traefik.fileMiddlewares.
        '';
      })
      badDockerMiddlewares
      ++ map (r: {
        assertion = false;
        message = ''
          Container "${r.container}": router "${r.router}" references middleware
          "${r.value}", which is not in stc.relics.docker.traefik.fileMiddlewares.

          STC cannot read your file provider's configuration, so that option is
          the only description it has of what your file provider defines. Either
          the name is a typo, or your file provider does define it and the option
          needs updating — the second case is the one that bites, because the
          option is what keeps this check honest for every other route.

          Declared: ${lib.concatStringsSep ", " cfg.fileMiddlewares}
        '';
      })
      badFileMiddlewares;

    virtualisation.oci-containers.containers."traefik" = {
      inherit (cfg) image;
      serviceName = "traefik";

      volumes =
        # Bind-mount the raw socket only when NOT going through the socket-proxy.
        lib.optional (!socketProxyEnabled) "/run/docker.sock:/var/run/docker.sock:ro"
        ++ [
          "${cfg.dataDir}/acme.json:/acme.json"
          "${cfg.dataDir}/logs:/logs"
        ]
        ++ (
          if cfg.dynamicConfigFile != null
          then [
            "${cfg.dataDir}/conf/traefik.yml:/etc/traefik/traefik.yml"
            "${cfg.dynamicConfigFile}:/etc/traefik/traefik_dynamic.yml"
          ]
          else [
            "${cfg.dataDir}/conf/traefik.yml:/etc/traefik/traefik.yml"
            "${cfg.dataDir}/conf/traefik_dynamic.yml:/etc/traefik/traefik_dynamic.yml"
          ]
        );

      extraOptions = dockerLib.mkHealthCheck {
        cmd = "traefik healthcheck";
        startPeriod = "10s";
      };

      labels = {
        "traefik.enable" = "false";
        "stc.docker/health-watch" = "true";
      };

      ports = [
        "80:80/tcp"
        "443:443/tcp"
      ];

      networks = ["web"] ++ lib.optional socketProxyEnabled socketProxyNetwork;
    };

    services.logrotate.settings.traefik = {
      files = "${cfg.dataDir}/logs/traefik.log";
      frequency = "daily";
      rotate = 14;
      # mkDefault on the four policy switches: log rotation policy belongs to
      # the operator (retention rules, a log shipper that wants uncompressed
      # files), these are public upstream settings, and changing any of them
      # breaks nothing this relic depends on. `files`, `frequency`, `rotate` and
      # `postrotate` stay pinned — they are wired to this relic's own dataDir
      # and to the USR1 reopen the comment below explains.
      compress = lib.mkDefault true;
      delaycompress = lib.mkDefault true;
      missingok = lib.mkDefault true;
      notifempty = lib.mkDefault true;
      # No copytruncate: it leaves a window where log lines written during the
      # copy are lost — lines CrowdSec would otherwise tail, so missed attacks.
      # Instead, rotate by rename and tell Traefik to reopen its log (USR1).
      postrotate = "${pkgs.docker}/bin/docker kill -s USR1 traefik || true";
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    systemd = {
      services = {
        "traefik" = let
          crowdsecDep = lib.optional crowdsecEnabled "crowdsec.service";
          socketDep = lib.optional socketProxyEnabled "docker-socket-proxy.service";
          deps = crowdsecDep ++ socketDep;
        in
          lib.mkIf (deps != []) {
            after = deps;
            # The socket-proxy is load-bearing for Traefik's Docker provider, so
            # it stays a hard requirement. CrowdSec is only a Wants: an IDS/IPS
            # that fails (and gets `docker kill`ed by the health-watch) must not
            # drag the reverse proxy — and everything it serves — down with it.
            requires = socketDep;
            wants = crowdsecDep;
          };
        "docker-network-web" =
          dockerLib.mkNetwork pkgs "web"
          // {
            # Traefik (and CrowdSec, when enabled) joins the "web" network at
            # startup. Without ordering, on the first boot a consumer can race
            # ahead of network creation and fail. requiredBy + before guarantee
            # the network exists before every consumer, not just Traefik.
            requiredBy = ["traefik.service"] ++ lib.optional crowdsecEnabled "crowdsec.service";
            before = ["traefik.service"] ++ lib.optional crowdsecEnabled "crowdsec.service";
          };
      };
      tmpfiles.rules = [
        "d ${cfg.dataDir}/logs 0750 0 0 -"
        "d ${cfg.dataDir}/conf 0750 0 0 -"
        "f ${cfg.dataDir}/acme.json 0600 0 0 -"
        "L+ ${cfg.dataDir}/conf/traefik.yml - - - - ${staticConfig}"
      ];
    };
  };
}
