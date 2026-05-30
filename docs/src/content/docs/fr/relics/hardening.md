---
title: Durcissement
description: Quatre reliques de durcissement — noyau, réseau, système de fichiers et SSH — plus le raccourci cogitator-hardening.
---

STC fournit quatre reliques de durcissement indépendantes. Chacune adresse une
surface d'attaque distincte et peut être activée individuellement.

## Durcissement du noyau

**Module :** `stc.nixosModules.relics-hardening-kernel`

**Option d'activation :** `stc.hardening.kernel.enable`

Applique des paramètres sysctl qui réduisent la surface d'attaque du noyau :

| Catégorie | Ce qu'elle fait |
|-----------|-----------------|
| Disposition mémoire | ASLR complet (`randomize_va_space = 2`), masquer les pointeurs noyau (`kptr_restrict = 2`), restreindre dmesg |
| Capacités non-privilégiées | Bloquer eBPF, perf, et la création de user namespaces pour les utilisateurs non-privilégiés |
| kexec / SysRq | Désactiver kexec (vecteur d'attaque de remplacement du noyau), désactiver SysRq |
| Core dumps | Désactiver entièrement — les core dumps peuvent exposer des secrets et des clés privées |
| Système de fichiers | Protéger les hardlinks, symlinks, FIFOs et fichiers réguliers contre les abus |

Les core dumps sont également désactivés via les limites de ressources PAM
(`security.pam.loginLimits`) par double précaution.

## Durcissement réseau

**Module :** `stc.nixosModules.relics-hardening-network`

**Option d'activation :** `stc.hardening.network.enable`

Applique uniquement le durcissement sysctl réseau. Ne gère **pas** le pare-feu —
utilise `networking.firewall` ou tes propres règles nftables/iptables pour le
contrôle des ports.

Paramètres sysctl appliqués :

| Catégorie | Ce qu'elle fait |
|-----------|-----------------|
| Anti-spoofing | Filtrage par chemin inverse sur toutes les interfaces |
| Rejet des redirections | Ignore les redirections ICMP dans toutes les directions, désactive l'envoi de redirections |
| Abus ICMP | Ignore les broadcasts ping et les réponses d'erreur erronées |
| Inondations SYN | Active les SYN cookies |

:::note[Le pare-feu est ta responsabilité]
Cette relique durcit la pile réseau du noyau. Les règles de pare-feu (ports ouverts,
réseau Docker, etc.) ne sont pas touchées. Cela permet à la relique d'être composable
avec Docker et d'autres configurations de conteneurs.
:::

## Durcissement du système de fichiers

**Module :** `stc.nixosModules.relics-hardening-filesystem`

**Option d'activation :** `stc.hardening.filesystem.enable`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.hardening.filesystem.tmpSize` | string | `"2G"` | Taille maximale du tmpfs /tmp |

Monte trois systèmes de fichiers avec des options restrictives :

| Point de montage | Ce qui change |
|------------------|---------------|
| `/tmp` | tmpfs avec `nosuid,noexec,nodev`, taille limitée |
| `/proc` | `hidepid=2,gid=proc` — les utilisateurs ne voient que leurs propres processus ; les services système gardent l'accès via le groupe `proc` |
| `/dev/shm` | tmpfs avec `nosuid,noexec,nodev`, limité à 256 Mio |

Le groupe `proc` est créé automatiquement. `systemd-logind` y est ajouté pour que
la gestion des sessions continue de fonctionner.

Le montage `/tmp noexec` empêche les attaquants d'écrire et d'exécuter du code dans un
répertoire accessible à tous — un vecteur d'exploitation classique.

## Durcissement SSH

**Module :** `stc.nixosModules.relics-hardening-ssh`

**Option d'activation :** `stc.hardening.ssh.enable`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.hardening.ssh.allowedTCPForwarding` | bool | `false` | Autoriser le TCP forwarding |

Configure OpenSSH avec :
- Authentification par mot de passe désactivée (clés uniquement)
- Connexion root désactivée
- MaxAuthTries : 3, LoginGraceTime : 20s
- Délai d'expiration des sessions inactives : 10 minutes (2 × 300s)
- X11, agent forwarding, tunneling, gateway ports : tous désactivés
- Chiffrements forts : ChaCha20-Poly1305, AES-256-GCM, AES-128-GCM
- MACs ETM uniquement : HMAC-SHA2-512-etm, HMAC-SHA2-256-etm
- Échange de clés : curve25519-sha256, DH groupe 16

## Exemple d'utilisation

Reliques individuelles :

```nix
modules = [
  stc.nixosModules.relics-hardening-kernel
  stc.nixosModules.relics-hardening-network
  stc.nixosModules.relics-hardening-filesystem
  stc.nixosModules.relics-hardening-ssh
  ./configuration.nix
];

# configuration.nix
{
  stc.hardening.kernel.enable = true;
  stc.hardening.network.enable = true;
  stc.hardening.filesystem.enable = true;
  stc.hardening.filesystem.tmpSize = "4G";
  stc.hardening.ssh.enable = true;

  # Le pare-feu est géré séparément — ouvre les ports ici selon tes besoins :
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
```

## Le raccourci cogitator-hardening

Pour le cas courant d'activation des quatre reliques avec les valeurs par défaut,
utilise [`cogitator-hardening`](/fr/cogitator/hardening/). Une option au lieu de quatre :

```nix
modules = [ stc.nixosModules.cogitator-hardening ];

# configuration.nix
{ stc.hardening.enable = true; }
```

Le cogitator ne t'empêche pas de régler les options individuelles ensuite —
`stc.hardening.filesystem.tmpSize` et `stc.hardening.ssh.allowedTCPForwarding`
restent configurables.
