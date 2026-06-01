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
| Capacités non-privilégiées | Bloquer eBPF et perf pour les utilisateurs non-privilégiés ; bloquer la création de user namespaces (voir note gaming) |
| kexec / SysRq | Désactiver kexec (vecteur d'attaque de remplacement du noyau), désactiver SysRq |
| Core dumps | Désactiver entièrement — les core dumps peuvent exposer des secrets et des clés privées |
| Système de fichiers | Protéger les hardlinks, symlinks, FIFOs et fichiers réguliers contre les abus |

Les core dumps sont également désactivés via les limites de ressources PAM
(`security.pam.loginLimits`) par double précaution.

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.hardening.kernel.gaming` | bool | `false` | Ne pas appliquer `kernel.unprivileged_userns_clone = 0` — Steam nécessite les user namespaces pour son runtime containerisé |

:::caution[Steam et user namespaces]
`kernel.unprivileged_userns_clone = 0` empêche Steam de démarrer. Définis
`stc.hardening.kernel.gaming = true` sur les machines gaming. Toutes les
autres restrictions noyau restent actives.
:::

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
| `stc.hardening.filesystem.shmSize` | string | `"256M"` | Taille maximale du tmpfs /dev/shm |
| `stc.hardening.filesystem.gaming` | bool | `false` | Retire `noexec` de /tmp et /dev/shm — requis pour Wine/Proton et DXVK |

Monte trois systèmes de fichiers avec des options restrictives :

| Point de montage | Ce qui change |
|------------------|---------------|
| `/tmp` | tmpfs avec `nosuid,noexec,nodev`, taille limitée — `noexec` omis si `gaming = true` |
| `/proc` | `hidepid=2,gid=proc` — les utilisateurs ne voient que leurs propres processus ; les services système gardent l'accès via le groupe `proc` |
| `/dev/shm` | tmpfs avec `nosuid,noexec,nodev`, taille limitée — `noexec` omis si `gaming = true` |

Le groupe `proc` est créé automatiquement. `systemd-logind` y est ajouté pour que
la gestion des sessions continue de fonctionner.

Le montage `/tmp noexec` empêche les attaquants d'écrire et d'exécuter du code dans un
répertoire accessible à tous — un vecteur d'exploitation classique.

:::caution[Wine, Proton et DXVK]
Wine et Proton extraient et exécutent des binaires dans `/tmp`. DXVK et
VKD3D-Proton mappent du code exécutable dans `/dev/shm`. Définis
`stc.hardening.filesystem.gaming = true` sur les machines gaming et augmente
`shmSize` à au moins `2G` pour les charges lourdes. Le durcissement `/proc`
n'est pas affecté.
:::

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

Machine gaming avec durcissement :

```nix
{
  stc.hardening.kernel.enable = true;
  stc.hardening.kernel.gaming = true;      # autorise les user namespaces pour Steam

  stc.hardening.filesystem.enable = true;
  stc.hardening.filesystem.gaming = true;  # autorise exec dans /tmp et /dev/shm
  stc.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D ont besoin de plus que 256M

  stc.hardening.network.enable = true;
  stc.hardening.ssh.enable = true;
}
```

## Le raccourci cogitator-hardening

Pour le cas courant d'activation des quatre reliques avec les valeurs par défaut,
utilise [`cogitator-hardening`](/stc/fr/cogitator/hardening/). Une option au lieu de quatre :

```nix
modules = [ stc.nixosModules.cogitator-hardening ];

# configuration.nix
{ stc.hardening.enable = true; }
```

Le cogitator ne t'empêche pas de régler les options individuelles ensuite —
`stc.hardening.filesystem.tmpSize` et `stc.hardening.ssh.allowedTCPForwarding`
restent configurables.
