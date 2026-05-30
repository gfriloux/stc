---
title: YubiKey
description: Two YubiKey relics — system-level pcscd and udev rules, plus user-level management tools and touch detector.
---

STC provides two independent YubiKey relics. The system relic handles the kernel
and daemon layer; the user relic handles the tooling and the graphical touch
notification.

## System Relic

**Module:** `stc.nixosModules.relics-yubikey-system`

**Enable option:** `stc.yubikey.enable`

Enables the PC/SC daemon and installs udev rules so the YubiKey is accessible
without root privileges.

### What it configures

```
services.pcscd.enable = true
services.udev.packages = [ pkgs.yubikey-personalization ]
```

**pcscd** is required for smart card operations: PIV slot, OpenPGP card, and
any operation that uses the CCID interface rather than raw HID.

The **udev rules** from `yubikey-personalization` grant access to the YubiKey
USB device for the logged-in user, avoiding `permission denied` errors.

## User Relic (Home Manager)

**Module:** `stc.homeModules.relics-yubikey-user`

**Enable option:** `stc.yubikey.enable`

Installs the YubiKey management suite and runs `yubikey-touch-detector` as a
user systemd service. The detector sends a libnotify notification whenever the
key waits for a physical touch (GPG signing, FIDO2 assertion, PIV PIN+touch).

### What it configures

Packages installed:

| Package | Purpose |
|---------|---------|
| `libfido2` | FIDO2/WebAuthn library and `fido2-token` CLI |
| `yubikey-manager` | `ykman` — configure slots, FIDO2, PIV, OpenPGP |
| `yubikey-touch-detector` | Fires libnotify when the key waits for a touch |
| `yubioath-flutter` | GUI TOTP/HOTP app (Yubico Authenticator) |

Service: `systemd.user.services.yubikey-touch-detector`
- Bound to `graphical-session.target` — starts and stops with the desktop session
- Runs `yubikey-touch-detector -libnotify`

## Usage Example

```nix
# flake.nix
nixosModules = [ stc.nixosModules.relics-yubikey-system ];
homeManagerModules = [ stc.homeModules.relics-yubikey-user ];

# configuration.nix
{ stc.yubikey.enable = true; }

# home.nix
{ stc.yubikey.enable = true; }
```

Both relics use `stc.yubikey.enable` but in separate evaluation contexts
(NixOS and Home Manager), so they do not conflict.
