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

  # Services that write their own authorized_keys file and would lose every way
  # in under systemAuthorizedKeysOnly. Reading config.services.<name>.enable is
  # safe: all five are nixpkgs modules, so the options exist in any NixOS
  # evaluation. That is NOT true of a module a consumer brings through their
  # flake (a secrets backend, say), where the option may simply not exist and
  # lib.mkIf false would not protect the reference.
  keyManagingServices =
    lib.filter (name: config.services.${name}.enable or false)
    ["gitea" "forgejo" "gitlab" "gitolite" "gerrit"];
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

    systemAuthorizedKeysOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Read authorized keys only from `/etc/ssh/authorized_keys.d/%u`, the file
        the NixOS module generates from
        `users.users.<name>.openssh.authorizedKeys.keys` — never from
        `~/.ssh/authorized_keys`.

        Default true: with the home directory in sshd's search path, anything
        able to write a file there grants persistent SSH access invisibly to the
        flake — a service compromised under that user, a careless container
        bind-mount, a sync tool. This pairs with `users.mutableUsers = false`,
        which STC's server-facing profiles already assume: the accounts come
        from the flake, so the keys should too.

        **This can lock you out.** A key that lives only in a user's
        `~/.ssh/authorized_keys` and is not declared in your configuration stops
        working at the next switch. Check before you deploy, not after.

        Software that manages its own `authorized_keys` — Git forges above all —
        loses access entirely. The relic refuses to build rather than let that
        happen silently; see the assertion below. Setting this to false restores
        the upstream behaviour for the whole host.

        Narrower escape: the underlying `services.openssh.authorizedKeysFiles` is
        a list and definitions merge, so a consumer can add one specific path
        back without giving up the lockdown.
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
      # Fail the build rather than let a Git forge lose its SSH access at
      # runtime, remotely, with nothing red anywhere. srvos excludes these
      # services automatically; that silently weakens the hardening on a host
      # nobody decided to weaken. A build error costs one line of configuration
      # and is impossible to miss — the lockout is not.
      {
        assertion = cfg.systemAuthorizedKeysOnly -> keyManagingServices == [];
        message = let
          names = lib.concatMapStringsSep " and " (name: "services.${name}") keyManagingServices;
          clause =
            if lib.length keyManagingServices > 1
            then "manage their own authorized_keys files and would"
            else "manages its own authorized_keys file and would";
        in "stc.relics.hardening.ssh: systemAuthorizedKeysOnly removes ~/.ssh/authorized_keys from sshd's search path, but ${names} ${clause} lose all SSH access. Either set stc.relics.hardening.ssh.systemAuthorizedKeysOnly = false on this host, or append the path the service needs to services.openssh.authorizedKeysFiles (it is a list — definitions merge, so the system path is kept).";
      }
    ];

    services.openssh = {
      enable = true;

      # The flake is the only source of SSH access. Expressed through the
      # upstream switch rather than a mkForce on authorizedKeysFiles: the option
      # is a list whose definitions merge, so a consumer keeps the ability to add
      # one path back (an SFTP-only account, a backup target) without turning the
      # whole lockdown off.
      authorizedKeysInHomedir = !cfg.systemAuthorizedKeysOnly;

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
