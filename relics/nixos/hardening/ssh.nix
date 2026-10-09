# Relic: SSH Hardening
# OpenSSH with strong cryptography and minimal attack surface.
#
# Scope: ANSSI-BP-028 does NOT cover sshd configuration. SSH hardening belongs to
# the separate ANSSI guide "Recommandations pour un usage sécurisé d'(Open)SSH".
#
# Password authentication is disabled. Keys only.
# The Omnissiah does not accept weak authentication.
# If you lose your key, that's between you and the Machine God.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.hardening.ssh;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "hardening" "ssh" "enable"] ["stc" "relics" "hardening" "ssh" "enable"])
    (lib.mkRenamedOptionModule ["stc" "hardening" "ssh" "allowedTCPForwarding"] ["stc" "relics" "hardening" "ssh" "allowedTCPForwarding"])
  ];

  options.stc.relics.hardening.ssh = {
    enable = lib.mkEnableOption "hardened OpenSSH server configuration";

    allowedTCPForwarding = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow TCP forwarding. Disabled by default on server VMs.";
    };

    perSourcePenalties = lib.mkOption {
      type = lib.types.str;
      default = "crash:3600s authfail:3600s max:86400s";
      description = ''
        sshd PerSourcePenalties: rate-limits misbehaving source addresses
        (auth failures, crashes) with escalating temporary blocks. OpenSSH ≥ 9.8
        enables this by default; STC sets explicit, tuned values. Set to
        "no" to disable.
      '';
    };

    banner = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      example = "Authorized access only. All activity is logged.";
      description = ''
        Text sent to the client before authentication (sshd Banner). The relic
        writes it to the store and points Banner at that file.

        Default null: no Banner directive at all. Banner wording is legal,
        site-specific content — STC cannot write it for you, and an unset
        banner changes nothing.

        For an existing file, use builtins.readFile ./banner.txt.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # mlkem768x25519-sha256 (post-quantum hybrid kex, first in KexAlgorithms)
    # requires OpenSSH ≥ 9.9. With inputs.nixpkgs.follows, a consumer pinned to an
    # older nixpkgs would otherwise get an sshd that refuses to start on an unknown
    # algorithm — a silent SSH lockout. Fail the build early with a clear message.
    assertions = [
      {
        assertion = lib.versionAtLeast config.services.openssh.package.version "9.9";
        message = "stc.relics.hardening.ssh: KexAlgorithms includes mlkem768x25519-sha256, which requires OpenSSH ≥ 9.9 (found ${config.services.openssh.package.version}). Upgrade nixpkgs, or override services.openssh.settings.KexAlgorithms to drop the post-quantum kex.";
      }
    ];

    services.openssh = {
      enable = true;

      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;

        # VERBOSE instead of the OpenSSH default INFO: it logs the fingerprint
        # of the public key each accepted connection used. With keys-only
        # authentication that fingerprint is the only thing tying a session to
        # a key — and therefore to a person.
        LogLevel = "VERBOSE";

        # Pre-authentication warning banner. Opt-in: null writes no Banner
        # directive at all (see the banner option). Interpolated to a store path
        # string, not left as a derivation: the sshd_config generator only
        # serialises strings, ints, bools and lists.
        Banner =
          if cfg.banner == null
          then null
          else "${pkgs.writeText "sshd-banner" cfg.banner}";

        MaxAuthTries = 3;
        LoginGraceTime = 20;
        MaxSessions = 5;

        # Rate-limit misbehaving source addresses (auth failures, crashes).
        PerSourcePenalties = cfg.perSourcePenalties;

        # Drop *unreachable* clients after 10 minutes (2 × 300s): if a client
        # stops answering keepalive probes (dropped link, crashed laptop) the
        # session is torn down. This does NOT disconnect merely idle sessions — a
        # reachable client answers the probes automatically and stays connected.
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;

        X11Forwarding = false;
        AllowAgentForwarding = false;
        AllowTcpForwarding = cfg.allowedTCPForwarding;
        PermitTunnel = false;
        GatewayPorts = "no";

        # Forward secrecy only, declared through typed settings so the NixOS
        # module validates them (extraConfig would bypass that). Post-quantum
        # hybrid key exchanges come first: hardening must not drop the PQ
        # protection that recent OpenSSH defaults already provide.
        KexAlgorithms = [
          "mlkem768x25519-sha256"
          "sntrup761x25519-sha512@openssh.com"
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group16-sha512"
        ];
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
        ];
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
      };
    };
  };
}
