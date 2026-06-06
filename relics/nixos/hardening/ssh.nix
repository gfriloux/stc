# Relic: SSH Hardening
# OpenSSH with strong cryptography and minimal attack surface.
#
# Password authentication is disabled. Keys only.
# The Omnissiah does not accept weak authentication.
# If you lose your key, that's between you and the Machine God.
{ config, lib, ... }:

let
  cfg = config.stc.relics.hardening.ssh;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "hardening" "ssh" "enable" ] [ "stc" "relics" "hardening" "ssh" "enable" ])
    (lib.mkRenamedOptionModule [ "stc" "hardening" "ssh" "allowedTCPForwarding" ] [ "stc" "relics" "hardening" "ssh" "allowedTCPForwarding" ])
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

        # Disconnect idle sessions after 10 minutes (2 × 300s).
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;

        X11Forwarding = false;
        AllowAgentForwarding = false;
        AllowTcpForwarding = cfg.allowedTCPForwarding;
        PermitTunnel = false;
        GatewayPorts = "no";
      };

      # Forward secrecy only. Algorithms chosen for resistance to known attacks.
      extraConfig = ''
        Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
        MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
        KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
      '';
    };
  };
}
