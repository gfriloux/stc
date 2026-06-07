# Relic: SSH Hardening
# OpenSSH with strong cryptography and minimal attack surface.
#
# Password authentication is disabled. Keys only.
# The Omnissiah does not accept weak authentication.
# If you lose your key, that's between you and the Machine God.
{
  config,
  lib,
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

        MaxAuthTries = 3;
        LoginGraceTime = 20;
        MaxSessions = 5;

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
