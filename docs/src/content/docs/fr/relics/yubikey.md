---
title: YubiKey
description: Deux reliques YubiKey — pcscd et règles udev côté système, outils de gestion et détecteur de toucher côté utilisateur.
---

STC fournit deux reliques YubiKey indépendantes. La relique système gère la couche
noyau et daemon ; la relique utilisateur gère les outils et la notification
graphique de toucher.

## Relique système

**Module :** `stc.nixosModules.relics-yubikey-system`

**Option d'activation :** `stc.relics.yubikey.enable`

Active le daemon PC/SC et installe les règles udev pour que la YubiKey soit
accessible sans privilèges root.

### Ce que ça configure

```
services.pcscd.enable = true
services.udev.packages = [ pkgs.yubikey-personalization ]
```

**pcscd** est nécessaire pour les opérations smart card : slot PIV, carte
OpenPGP, et toute opération utilisant l'interface CCID plutôt que le HID brut.

Les **règles udev** de `yubikey-personalization` donnent accès au périphérique
USB YubiKey à l'utilisateur connecté, évitant les erreurs de permission.

## Relique utilisateur (Home Manager)

**Module :** `stc.homeModules.relics-yubikey-user`

**Option d'activation :** `stc.relics.yubikey.enable`

Installe la suite de gestion YubiKey et exécute `yubikey-touch-detector` comme
service systemd utilisateur. Le détecteur envoie une notification libnotify
chaque fois que la clé attend un toucher physique (signature GPG, assertion
FIDO2, PIN+toucher PIV).

### Ce que ça configure

Paquets installés :

| Paquet | Rôle |
|--------|------|
| `libfido2` | Bibliothèque FIDO2/WebAuthn et CLI `fido2-token` |
| `yubikey-manager` | `ykman` — configurer les slots, FIDO2, PIV, OpenPGP |
| `yubikey-touch-detector` | Envoie une notification libnotify lors de l'attente d'un toucher |
| `yubioath-flutter` | Application TOTP/HOTP graphique (Yubico Authenticator) |

Service : `systemd.user.services.yubikey-touch-detector`
- Lié à `graphical-session.target` — démarre et s'arrête avec la session graphique
- Exécute `yubikey-touch-detector -libnotify`

## Exemple d'utilisation

```nix
# flake.nix
nixosModules = [ stc.nixosModules.relics-yubikey-system ];
homeManagerModules = [ stc.homeModules.relics-yubikey-user ];

# configuration.nix
{ stc.relics.yubikey.enable = true; }

# home.nix
{ stc.relics.yubikey.enable = true; }
```

Les deux reliques utilisent `stc.relics.yubikey.enable` mais dans des contextes
d'évaluation séparés (NixOS et Home Manager), elles ne sont donc pas en conflit.
