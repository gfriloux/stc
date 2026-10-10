---
title: Durcissement
description: Cinq reliques de durcissement — noyau, réseau, système de fichiers, SSH et blacklist de modules — plus le raccourci cogitator-hardening.
---

STC fournit cinq reliques de durcissement indépendantes. Chacune adresse une
surface d'attaque distincte et peut être activée individuellement.

## Durcissement du noyau

**Module :** `stc.nixosModules.relics-hardening-kernel`

**Option d'activation :** `stc.relics.hardening.kernel.enable`

Applique des paramètres sysctl qui réduisent la surface d'attaque du noyau :

| Catégorie | Ce qu'elle fait |
|-----------|-----------------|
| Disposition mémoire | ASLR complet (`randomize_va_space = 2`), masquer les pointeurs noyau (`kptr_restrict = 2`), restreindre dmesg |
| Capacités non-privilégiées | Bloquer eBPF et perf pour les utilisateurs non-privilégiés ; restreindre ptrace aux enfants directs (`yama.ptrace_scope = 1`) |
| kexec / SysRq | Désactiver kexec (vecteur d'attaque de remplacement du noyau), désactiver SysRq |
| Fautes noyau | Paniquer sur un oops (`panic_on_oops = 1`) et redémarrer 30 s plus tard (`panic = 30`) au lieu de poursuivre dans un état dont le noyau ne peut plus répondre |
| Core dumps | Désactiver entièrement — les core dumps peuvent exposer des secrets et des clés privées |
| Système de fichiers | Protéger les hardlinks, symlinks, FIFOs et fichiers réguliers contre les abus |

Les core dumps sont désactivés via `systemd.coredump.enable = false` et les
limites de ressources PAM (`security.pam.loginLimits`) par double précaution.

:::caution[Paniquer sur un oops est un vrai compromis de disponibilité]
Un oops noyau que la machine aurait auparavant survécu la met désormais à terre
et la redémarre. Cela ne couvre que les fautes réelles (`Oops:` / `BUG:` dans
`dmesg`), jamais les traces `WARNING: ... at <fichier>:<ligne>` qu'émet un défaut
bénin de pilote. Vérifie `cat /proc/sys/kernel/tainted` sur l'hôte : si le bit 7
(`128`) ne s'allume jamais sous ta charge de travail, aucun oops n'a eu lieu et
le réglage ne te coûte rien. Pour garder une machine figée en vue d'un
post-mortem plutôt que de redémarrer :
`boot.kernel.sysctl."kernel.panic" = lib.mkForce 0;`. Raisonnement complet dans
[Fidélité ANSSI-BP-028](/stc/fr/reference/anssi-bp-028/).
:::

## Durcissement réseau

**Module :** `stc.nixosModules.relics-hardening-network`

**Option d'activation :** `stc.relics.hardening.network.enable`

Applique uniquement le durcissement sysctl réseau. Ne gère **pas** le pare-feu —
utilise `networking.firewall` ou tes propres règles nftables/iptables pour le
contrôle des ports.

Paramètres sysctl appliqués :

| Catégorie | Ce qu'elle fait |
|-----------|-----------------|
| Anti-spoofing | Filtrage par chemin inverse sur toutes les interfaces |
| Rejet des redirections | Ignore les redirections ICMP dans toutes les directions, désactive l'envoi de redirections |
| Routage à la source | Rejette les paquets source-routés (IPv4 + IPv6) |
| Journalisation des martiens | Journalise les paquets à adresse source impossible (`log_martians`) |
| Abus ICMP | Ignore les broadcasts ping et les réponses d'erreur erronées |
| Inondations SYN | Active les SYN cookies ; protection anti-assassinat TIME_WAIT (`tcp_rfc1337`) |
| JIT eBPF | Durcit le JIT contre les attaques par spraying (`bpf_jit_harden = 2`) |

**Options :**

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.hardening.network.strictReversePathFilter` | bool | `true` | Filtrage par chemin inverse strict (`1`). Mettre à `false` pour le mode loose (`2`) sur les hôtes à routage asymétrique / multi-homed / WireGuard où le mode strict bloque le trafic de retour légitime. |
| `stc.relics.hardening.network.strictArp` | bool | `false` | Durcissement ARP (`arp_ignore=1`, `arp_announce=2`). Désactivé par défaut : peut casser les hôtes multi-homed, les bridges Linux et le réseau Docker. À activer uniquement sur les hôtes single-homed. |
| `stc.relics.hardening.network.strictIpv6RouterAdvertisements` | bool | `false` | Refuse les Router Advertisements IPv6 (`accept_ra=0`). Désactivé par défaut : isole tout hôte adressé par SLAAC. À activer là où l'IPv6 est statique ou inutilisée, pour qu'un voisin sur un segment non fiable ne puisse pas injecter un préfixe et une route par défaut. |

:::note[Le pare-feu est ta responsabilité]
Cette relique durcit la pile réseau du noyau. Les règles de pare-feu (ports ouverts,
réseau Docker, etc.) ne sont pas touchées. Cela permet à la relique d'être composable
avec Docker et d'autres configurations de conteneurs.
:::

## Durcissement du système de fichiers

**Module :** `stc.nixosModules.relics-hardening-filesystem`

**Option d'activation :** `stc.relics.hardening.filesystem.enable`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.hardening.filesystem.tmpSize` | string | `"2G"` | Taille maximale du tmpfs /tmp |
| `stc.relics.hardening.filesystem.shmSize` | string | `"256M"` | Taille maximale du tmpfs /dev/shm |
| `stc.relics.hardening.filesystem.gaming` | bool | `false` | Retire `noexec` de /tmp et /dev/shm — requis pour Wine/Proton et DXVK |

Monte trois systèmes de fichiers avec des options restrictives :

| Point de montage | Ce qui change |
|------------------|---------------|
| `/tmp` | tmpfs avec `nosuid,noexec,nodev`, taille limitée — `noexec` omis si `gaming = true` |
| `/proc` | `hidepid=2,gid=proc` — les utilisateurs ne voient que leurs propres processus ; les services système gardent l'accès via le groupe `proc` |
| `/dev/shm` | tmpfs avec `nosuid,noexec,nodev`, taille limitée — `noexec` omis si `gaming = true` |

Le groupe `proc` est créé automatiquement. `systemd-logind` y est ajouté pour que
la gestion des sessions continue de fonctionner.

:::caution[hidepid et desktop / supervision]
`hidepid=2` masque aussi les processus des autres utilisateurs à polkit, aux agents
D-Bus utilisateur et à plusieurs exporters Prometheus, ce qui peut les faire
dysfonctionner. Seul `systemd-logind` est câblé d'office dans le groupe `proc`.
Quand tu composes le durcissement filesystem avec un desktop (ex. `cogitator-plasma`)
ou des exporters, ajoute les services concernés au groupe `proc` via
`systemd SupplementaryGroups`, ou laisse le durcissement filesystem désactivé sur ces
hôtes. La relique émet un warning de build quand elle détecte un desktop avec ce
durcissement.
:::

Le montage `/tmp noexec` empêche les attaquants d'écrire et d'exécuter du code dans un
répertoire accessible à tous — un vecteur d'exploitation classique.

:::caution[Wine, Proton et DXVK]
Wine et Proton extraient et exécutent des binaires dans `/tmp`. DXVK et
VKD3D-Proton mappent du code exécutable dans `/dev/shm`. Définis
`stc.relics.hardening.filesystem.gaming = true` sur les machines gaming et augmente
`shmSize` à au moins `2G` pour les charges lourdes. Le durcissement `/proc`
n'est pas affecté.
:::

## Durcissement SSH

**Module :** `stc.nixosModules.relics-hardening-ssh`

**Option d'activation :** `stc.relics.hardening.ssh.enable`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.hardening.ssh.allowedTCPForwarding` | bool | `false` | Autoriser le TCP forwarding |
| `stc.relics.hardening.ssh.perSourcePenalties` | string | `"crash:3600s authfail:3600s max:86400s"` | `PerSourcePenalties` de sshd — limite le débit des adresses sources fautives avec des blocages progressifs. Mettre à `"no"` pour désactiver. |
| `stc.relics.hardening.ssh.banner` | null ou lines | `null` | Texte du bandeau d'avertissement affiché avant authentification. La relique l'écrit dans le store et pointe le `Banner` de sshd dessus. `null` n'émet aucune directive `Banner`. |

Configure OpenSSH avec :
- Authentification par mot de passe désactivée (clés uniquement)
- Connexion root désactivée
- `LogLevel VERBOSE` — journalise l'empreinte de la clé publique utilisée par
  chaque connexion acceptée. Avec une authentification par clés uniquement,
  cette empreinte est la seule chose qui relie une session à une clé, donc à
  une personne.
- MaxAuthTries : 3, LoginGraceTime : 20s
- Pénalités par source : limite les échecs d'auth / crashs par adresse source
- Délai d'expiration des sessions inactives : 10 minutes (2 × 300s)
- X11, agent forwarding, tunneling, gateway ports : tous désactivés
- Chiffrements forts : ChaCha20-Poly1305, AES-256-GCM, AES-128-GCM
- MACs ETM uniquement : HMAC-SHA2-512-etm, HMAC-SHA2-256-etm
- Échange de clés : hybrides post-quantiques en tête (mlkem768x25519-sha256,
  sntrup761x25519-sha512), puis curve25519-sha256 et DH groupe 16

:::note[Le bandeau est opt-in]
Le texte d'un bandeau est du contenu juridique propre au site — STC ne peut pas
l'écrire à ta place, donc le défaut est `null` et aucune directive `Banner` n'est
émise tant que tu n'en définis pas un :

```nix
stc.relics.hardening.ssh.banner = ''
  Accès réservé aux personnes autorisées. Toute activité est journalisée.
'';
```

Le texte est déjà dans un fichier ? `banner = builtins.readFile ./banner.txt;`.
:::

:::caution[Nécessite OpenSSH ≥ 9.9]
L'échange de clés `mlkem768x25519-sha256` requiert OpenSSH ≥ 9.9. La relique
l'asserte au build, donc un consommateur épinglé (via `inputs.nixpkgs.follows`)
sur un nixpkgs plus ancien obtient une erreur de build claire au lieu d'un sshd
qui refuse silencieusement de démarrer — ce qui te verrouillerait dehors. Mets à
jour nixpkgs, ou surcharge `services.openssh.settings.KexAlgorithms` pour retirer
le kex post-quantique.
:::

## Blacklist de modules

**Module :** `stc.nixosModules.relics-hardening-modules`

**Option d'activation :** `stc.relics.hardening.modules.enable`

Blackliste des modules noyau à haut risque ou inutilisés pour réduire la surface
d'attaque :

| Famille | Modules | Pourquoi |
|---------|---------|----------|
| FireWire (DMA) | `firewire-core`, `firewire-ohci`, `firewire-sbp2` | Un périphérique hostile peut lire/écrire la mémoire physique via le bus |
| Protocoles réseau rares | `dccp`, `sctp`, `rds`, `tipc` | Quasi jamais utilisés sur un hôte normal, mais source récurrente de CVE noyau |
| Systèmes de fichiers legacy | `cramfs`, `freevxfs`, `jffs2`, `hfs`, `hfsplus` | Pilotes que rien ne monte sur un hôte normal, et autant de parseurs atteignables depuis un média amovible |

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.hardening.modules.extraBlacklist` | liste de string | `[]` | Modules supplémentaires à blacklister, fusionnés avec les défauts (ex. `[ "bluetooth" "uvcvideo" ]`) |

C'est la forme *souple* de l'ANSSI-BP-028 R10 (désactiver les modules inutilisés) :
une blacklist ciblée plutôt que le verrouillage total `kernel.modules_disabled=1`,
qui casserait le chargement de modules à la demande et nécessite une évaluation au
cas par cas.

### Hors blacklist par défaut : `udf` et `usb-storage`

Les référentiels habituels citent aussi `udf` (média optique) et `usb-storage`.
Les deux restent hors des défauts ici, parce qu'ils ont encore des usages
légitimes — monter un DVD/Blu-ray, installer depuis une clé USB — et parce que
`boot.blacklistedKernelModules` est une liste : `extraBlacklist` y ajoute, rien
n'en retire. Un défaut qui s'avérerait mauvais ne laisserait aucune surcharge
propre. Sur un hôte où aucun des deux ne sert, mets-les dans `extraBlacklist` :

```nix
stc.relics.hardening.modules.extraBlacklist = [ "udf" "usb-storage" ];
```

:::caution[FireWire, protocoles rares, systèmes de fichiers legacy]
Si un hôte a réellement besoin de FireWire (ex. une interface audio), d'un des
protocoles rares (SCTP pour certaines piles téléphonie/SIP) ou d'un des systèmes
de fichiers legacy (`hfsplus` sur un Mac en dual-boot), active les autres
reliques à la carte plutôt que celle-ci, ou surcharge
`boot.blacklistedKernelModules`.
:::

## Exemple d'utilisation

Reliques individuelles :

```nix
modules = [
  stc.nixosModules.relics-hardening-kernel
  stc.nixosModules.relics-hardening-network
  stc.nixosModules.relics-hardening-filesystem
  stc.nixosModules.relics-hardening-ssh
  stc.nixosModules.relics-hardening-modules
  ./configuration.nix
];

# configuration.nix
{
  stc.relics.hardening.kernel.enable = true;
  stc.relics.hardening.network.enable = true;
  stc.relics.hardening.filesystem.enable = true;
  stc.relics.hardening.filesystem.tmpSize = "4G";
  stc.relics.hardening.ssh.enable = true;
  stc.relics.hardening.modules.enable = true;

  # Le pare-feu est géré séparément — ouvre les ports ici selon tes besoins :
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
```

Machine gaming avec durcissement :

```nix
{
  stc.relics.hardening.kernel.enable = true;

  stc.relics.hardening.filesystem.enable = true;
  stc.relics.hardening.filesystem.gaming = true;  # autorise exec dans /tmp et /dev/shm
  stc.relics.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D ont besoin de plus que 256M

  stc.relics.hardening.network.enable = true;
  stc.relics.hardening.ssh.enable = true;
}
```

## Le raccourci cogitator-hardening

Pour le cas courant d'activation des cinq reliques avec les valeurs par défaut,
utilise [`cogitator-hardening`](/stc/fr/cogitator/hardening/). Une option au lieu de cinq :

```nix
modules = [ stc.nixosModules.cogitator-hardening ];

# configuration.nix
{ stc.cogitator.hardening.enable = true; }
```

Le cogitator ne t'empêche pas de régler les options individuelles ensuite —
`stc.relics.hardening.filesystem.tmpSize` et `stc.relics.hardening.ssh.allowedTCPForwarding`
restent configurables.
