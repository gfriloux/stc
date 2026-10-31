---
title: Durcissement
description: Sept reliques de durcissement — noyau, réseau, système de fichiers, SSH, blacklist de modules, accès aux ordonnanceurs et audit — plus le raccourci cogitator-hardening.
---

STC fournit sept reliques de durcissement indépendantes. Chacune adresse une
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
`boot.kernel.sysctl."kernel.panic" = lib.mkForce 0;` — et sur un profil serveur,
aussi `stc.relics.serverSurvivability.panicReboot = false;`, dont le `panic=30`
sur la ligne de commande couvre le boot avant que le sysctl s'applique.
Raisonnement complet dans
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
| `stc.relics.hardening.filesystem.varTmp.enable` | bool | `true` | Remonte /var/tmp sur lui-même avec `nosuid,nodev,noexec` |
| `stc.relics.hardening.filesystem.gaming` | bool | `false` | Retire `noexec` de /tmp, /var/tmp et /dev/shm — requis pour Wine/Proton et DXVK |

Monte quatre systèmes de fichiers avec des options restrictives :

| Point de montage | Ce qui change |
|------------------|---------------|
| `/tmp` | tmpfs avec `nosuid,noexec,nodev`, taille limitée — `noexec` omis si `gaming = true` |
| `/var/tmp` | lié sur lui-même avec `nosuid,noexec,nodev` — reste sur disque, `noexec` omis si `gaming = true` |
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

### /var/tmp

`/var/tmp` est l'autre répertoire accessible à tous en écriture, il reçoit donc
les trois mêmes options. Il est **lié sur lui-même** et non sur le tmpfs `/tmp` :
ses données restent là où ton layout les met et gardent la persistance que ce
layout leur donne, et la relique n'a pas besoin de connaître le layout disque.
Sur un disque classique, elles survivent à un reboot (sa raison d'être selon le
FHS). Sur un hôte impermanence, `/var/tmp` vit sur la racine restaurée, donc il
est vidé au boot, comme avant : le montage crée le répertoire si besoin
(`X-mount.mkdir`), puis `systemd-tmpfiles` pose son mode `1777`.

Persister `/var/tmp` via impermanence (`extraDirectories` ou
`environment.persistence`) est **refusé par une assertion** : le bind mount de
persistance remplacerait le montage durci et ferait tomber les trois options
sans rien dire. Soit tu arrêtes de le persister, soit tu poses
`varTmp.enable = false` pour accepter `/var/tmp` sans elles. Les builds Nix ne sont pas concernés :
`nix-daemon` compile sous `/nix/var/nix/builds`.

Si ton layout monte déjà `/var/tmp` (dataset ou partition dédiés), les deux
définitions entrent en conflit à l'évaluation. Pose `varTmp.enable = false` et
mets les options sur ton propre montage :

```nix
stc.relics.hardening.filesystem.varTmp.enable = false;
fileSystems."/var/tmp".options = [ "nosuid" "nodev" "noexec" ];
```

### /home

La relique ne touche pas `/home` : elle ne peut pas savoir si `/home` est un
montage séparé, et sur les layouts ZFS de STC il ne l'est pas (seuls `/`, `/nix`
et `/persist` le sont). Si `/home` est un montage séparé dans ton layout, ajoute
les options toi-même :

```nix
fileSystems."/home".options = [ "nosuid" "nodev" ];
```

:::caution[Wine, Proton et DXVK]
Wine et Proton extraient et exécutent des binaires dans `/tmp`. DXVK et
VKD3D-Proton mappent du code exécutable dans `/dev/shm`. `/var/tmp` suit `/tmp`
par cohérence. Définis
`stc.relics.hardening.filesystem.gaming = true` sur les machines gaming et augmente
`shmSize` à au moins `2G` pour les charges lourdes. Le durcissement `/proc`
n'est pas affecté.
:::

## Durcissement SSH

**Module :** `stc.nixosModules.relics-hardening-ssh`

**Option d'activation :** `stc.relics.hardening.ssh.enable`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.hardening.ssh.allowedTCPForwarding` | bool | `false` | Autoriser le TCP forwarding. Pilote aussi `StreamLocalBindUnlink`, qui n'a d'objet que si le forwarding est autorisé. |
| `stc.relics.hardening.ssh.allowedX11Forwarding` | bool | `false` | Autoriser le X11 forwarding. Nécessaire à un poste qui relaie une application graphique distante, et à un hôte qui est aussi client Slurm. |
| `stc.relics.hardening.ssh.allowedAgentForwarding` | bool | `false` | Autoriser le forwarding d'agent SSH — rebondir par un bastion avec son propre agent. |
| `stc.relics.hardening.ssh.allowedTunnel` | bool | `false` | Autoriser le forwarding de périphérique tun (`PermitTunnel`). |
| `stc.relics.hardening.ssh.systemAuthorizedKeysOnly` | bool | `true` | Ne lire les clés autorisées que dans `/etc/ssh/authorized_keys.d/%u` — ce que déclare le flake — jamais dans `~/.ssh/authorized_keys`. **Peut vous verrouiller dehors** ; voir plus bas. |
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
- Clés autorisées lues uniquement dans `/etc/ssh/authorized_keys.d/%u`
- `UseDns no` — aucun aller-retour DNS inverse par connexion. Celui-ci est le
  défaut amont, pas un réglage de la relique ; il figure ici parce que la
  question revient.
- Chiffrements forts : ChaCha20-Poly1305, AES-256-GCM, AES-128-GCM
- MACs ETM uniquement : HMAC-SHA2-512-etm, HMAC-SHA2-256-etm
- Échange de clés : hybrides post-quantiques en tête (mlkem768x25519-sha256,
  sntrup761x25519-sha512), puis curve25519-sha256 et DH groupe 16

:::danger[À lire avant d'activer sur une machine que vous ne pouvez pas atteindre physiquement]
`systemAuthorizedKeysOnly` est actif par défaut. Il retire
`~/.ssh/authorized_keys` du chemin de recherche de sshd, donc **une clé qui
n'est pas déclarée dans votre configuration cesse de fonctionner au prochain
switch.**

Sur un hôte entièrement déclaratif, rien ne change en pratique : le module
écrit déjà chaque clé déclarée dans `/etc/ssh/authorized_keys.d/<user>`, qui
reste le seul fichier lu. Ce qui change, c'est que le flake devient toute la
vérité — et c'est précisément l'objectif. Un service compromis sous le compte
d'un utilisateur, un bind-mount de conteneur mal cadré ou un outil de
synchronisation ne peuvent plus s'accorder un accès SSH persistant de manière
invisible.

Vérifiez avant de déployer, pas après :

```bash
# sur la machine cible — toutes les clés qui vont cesser de fonctionner
sudo find /home /root -maxdepth 3 -name authorized_keys -exec ls -l {} +
```

Gardez une seconde voie d'accès (console, hors bande, une session déjà
ouverte) pendant le premier switch.
:::

:::caution[Les logiciels qui gèrent leurs propres clés]
Toute une classe de logiciels écrit son propre `authorized_keys` et perd tout
accès sous cette option. Les **forges Git** en sont le cas évident, et la
relique refuse de construire dès qu'elle en voit une :

```
stc.relics.hardening.ssh: systemAuthorizedKeysOnly removes ~/.ssh/authorized_keys
from sshd's search path, but services.gitea manages its own authorized_keys file
and would lose all SSH access. Either set
stc.relics.hardening.ssh.systemAuthorizedKeysOnly = false on this host, or append
the path the service needs to services.openssh.authorizedKeysFiles (it is a list
— definitions merge, so the system path is kept).
```

L'assertion couvre `services.gitea`, `services.forgejo`, `services.gitlab`,
`services.gitolite` et `services.gerrit`. **À lire comme un échantillon de la
classe, pas comme une liste exhaustive** — tout ce qui attend une gestion de
clés par utilisateur est concerné et n'obtient aucune erreur de build : comptes
SFTP-only, cibles de sauvegarde qui laissent le pair ajouter sa clé,
provisionnement maison qui dépose une clé dans `~/.ssh`.

srvos désactive le verrou automatiquement pour ces services. STC s'y refuse :
une exclusion automatique affaiblit le durcissement sur une machine où personne
ne l'a décidé. Vous obtenez un build en échec et deux sorties — couper l'option
pour cet hôte, ou ajouter le seul chemin nécessaire :

```nix
# conserve le verrou, ajoute un emplacement supplémentaire
services.openssh.authorizedKeysFiles = ["/etc/ssh/forge_keys/%u"];
```

`authorizedKeysFiles` est une liste et les définitions fusionnent : le chemin
système reste en place.
:::

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

## Accès aux ordonnanceurs

**Module :** `stc.nixosModules.relics-hardening-scheduler`

**Option d'activation :** `stc.relics.hardening.scheduler.enable`

Restreint les ordonnanceurs classiques — `cron` et `at` — à une liste
d'utilisateurs explicite, `["root"]` par défaut.

Cette relique **n'active jamais d'ordonnanceur**. Tout son bloc de configuration
est gardé par `mkIf config.services.cron.enable` et
`mkIf config.services.atd.enable`, elle est donc inerte sur un hôte qui
ordonnance par timers systemd — c'est-à-dire toutes les machines STC. Elle
existe pour l'hôte qui en fait tourner un, car nixpkgs ouvre délibérément les
deux à tous les utilisateurs locaux :

| Comportement amont | Conséquence |
|---|---|
| Vixie cron n'autorise que root quand ni `cron.allow` ni `cron.deny` n'existe | Le `preStart` du module NixOS pose un `/var/cron/cron.deny` vide — « *By default, allow all users to create a crontab* » — ce qui inverse ce défaut |
| Le `preStart` d'`atd` pose un `/etc/at/at.deny` vide | Même effet : personne n'est refusé, donc tout le monde est autorisé |

Et cron peut s'activer tout seul : `services.cron.enable` vaut
`mkDefault (allFiles != [])`, donc tout module tiers qui pose un
`services.cron.systemCronJobs` démarre le démon — ouvert à tous — sans que le
consommateur l'ait demandé. C'est ce cas qui justifie du code plutôt qu'un
paragraphe de conseil.

**Options :**

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.hardening.scheduler.allowedUsers` | liste de str | `[ "root" ]` | Utilisateurs autorisés à ordonnancer des travaux via `crontab` et `at`. Écrits dans `/var/cron/cron.allow` et `/etc/at/at.allow`, qui l'emportent tous deux sur le `*.deny` permissif créé par les modules amont. |

Attention aux chemins : NixOS utilise `/var/cron/cron.allow` et
`/etc/at/at.allow`, pas les `/etc/cron.allow` et `/etc/at.allow` que citent les
référentiels dérivés de RHEL. Un hôte qui écrit ces derniers n'a rien restreint.

Une crontab système déclarée via `services.cron.systemCronJobs` n'est pas
concernée : elle tourne depuis `/etc/crontab` en tant que root et ne passe jamais
par la commande `crontab` par utilisateur que cette liste contrôle.

:::caution[Ceci peut retirer crontab à des utilisateurs existants]
Si un hôte fait déjà tourner cron — y compris via l'auto-activation ci-dessus —
et que des utilisateurs non-root s'appuient sur `crontab`, activer cette relique
les refuse. Liste-les dans `allowedUsers` :

```nix
stc.relics.hardening.scheduler.allowedUsers = [ "root" "deploy" ];
```

Les deux fichiers d'autorisation sont réécrits depuis le store Nix à chaque
activation, donc un `/var/cron/cron.allow` édité à la main ne survivra pas à un
rebuild. C'est tout l'intérêt de déclarer la liste ici, mais cela remplacera
silencieusement une liste entretenue à la main.
:::

## Audit

**Module :** `stc.nixosModules.relics-hardening-audit`

**Option d'activation :** `stc.relics.hardening.audit.enable`

Fait tourner auditd avec un jeu de règles de base chargé au boot (ANSSI-BP-028
R73). La relique s'appuie sur les modules amont `security.audit` et
`security.auditd` : elle ajoute les règles et deux valeurs par défaut, rien
d'autre.

**Options :**

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.hardening.audit.enable` | bool | `false` | Active auditd et le jeu de règles de base |
| `stc.relics.hardening.audit.immutable` | bool | `false` | Verrouille la configuration d'audit jusqu'au reboot (`auditctl -e 2`) |

La relique pose aussi `security.audit.backlogLimit = 8192` (`mkDefault` ;
l'amont est à 1024), pour ne pas perdre les évènements émis avant le démarrage
d'auditd. La ligne de commande du noyau reçoit `audit=1 audit_backlog_limit=8192`.

**Ce qui est enregistré** — à chercher avec `ausearch -i -k <clé>` :

| Clé | Règle | Enregistre |
|-----|-------|------------|
| `identity` | surveillance de `/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow` | Toute écriture ou changement d'attribut |
| `scope` | surveillance de `/etc/sudoers`, `/etc/sudoers.d` | Toute écriture ou changement d'attribut |
| `user_emulation` | `execve`/`execveat` avec `euid != uid`, depuis une session ouverte | Lancer `sudo`, `su` ou tout programme setuid |
| `kernel_modules` | `init_module`, `finit_module`, `delete_module` | Chaque chargement et déchargement de module, y compris par udev |
| `mounts` | `mount`, `umount2`, depuis une session ouverte | Les montages d'un utilisateur connecté, `sudo mount` compris |

Sur x86_64, les trois règles d'appels système existent aussi pour la table
32 bits (`arch=b32`), le contournement classique d'une règle 64 bits seule.

Les connexions et déconnexions n'ont pas besoin de règle. libpam lui-même
(nixpkgs le construit avec le support d'audit) émet les enregistrements
`USER_AUTH`, `USER_START` et `USER_END` pour toute pile PAM, connexion SSH par
clé comprise : `ausearch -i -m USER_START`.

Les deux règles « depuis une session ouverte » filtrent sur `auid!=unset`.
Pour `mounts`, c'est une nécessité : sans filtre, systemd qui démonte
`/run/credentials/<unité>` à chaque démarrage d'unité noie le journal. Pour
`user_emulation`, c'est la forme du référentiel habituel. Un démon qui lance `mount` ou un programme
setuid de lui-même n'est donc pas enregistré ; tout ce que fait un utilisateur
connecté l'est, même via `sudo`, car l'uid d'audit suit la session.

:::danger[Une seule règle invalide coupe tout l'audit]
L'amont charge toutes les règles d'un seul `auditctl -R` dans
`audit-rules-nixos.service`, très tôt au boot, avant `sysinit.target`. Si une
ligne échoue, le chargement s'arrête, l'unité désactive l'audit en sortant, et
**auditd continue de tourner comme si de rien n'était**. La seule trace est
l'unité en échec :

```bash
systemctl status audit-rules-nixos.service   # doit être active
auditctl -s | head -1                         # doit afficher « enabled 1 » (2 avec immutable)
```

Une surveillance sous `/var` est la façon classique d'en arriver là : `/var/log`
n'existe pas encore à ce moment-là, et sur un hôte impermanence c'est un bind
mount posé plus tard. C'est pour cela que la base n'a aucune surveillance de
`wtmp` ou de `lastlog`. Garde tes propres surveillances sur des chemins
présents sur la racine dès le départ, comme `/etc`.
:::

**Ajouter des règles.** Ajoute-les directement dans `security.audit.rules`.
Une définition simple passe après la base ; une exclusion (`-a never`) doit
venir en premier pour agir, donc donne-lui `lib.mkBefore` :

```nix
security.audit.rules = [
  "-w /etc/nixos -p wa -k nixos-config"
];
```

```nix
# Ignorer tout ce que fait l'uid 990, avant les règles de base.
security.audit.rules = lib.mkBefore [
  "-a never,exit -F uid=990"
];
```

Donne les uid en nombres. auditctl résout un nom d'utilisateur au chargement
des règles, et un nom inconnu — un compte qui n'existe pas encore si tôt au
boot — fait échouer tout le chargement.

**Journaux.** Les enregistrements vont dans `/var/log/audit/audit.log`. NixOS
n'écrit aucun réglage de rotation et les défauts internes d'auditd ne
rotent jamais : la relique pose donc cinq fichiers de 8 Mio
(`security.auditd.settings.{max_log_file,num_logs,max_log_file_action}`, tous
en `mkDefault`), soit 40 Mio au plus. Sur un hôte impermanence, `/var/log` est
persisté : la trace survit au rollback. journald reçoit aussi une copie de
chaque enregistrement (`journalctl _TRANSPORT=audit`) ; pour garder l'audit
hors du journal, pose `systemd.sockets.systemd-journald-audit.enable = false;`.

**`immutable`.** Avec `immutable = true`, root ne peut plus modifier les règles
jusqu'au prochain reboot. Un `nixos-rebuild switch` qui les change fait échouer
l'unité `audit-rules-nixos`, et les nouvelles règles ne s'appliquent qu'après
un reboot. Active-le une fois le jeu de règles stabilisé, pas pendant que tu le
règles encore. Passe par cette option plutôt que par
`security.audit.enable = "lock"` : la relique écrit déjà cette option, et une
seconde définition entre en conflit.

## Pas une relique : sudo

Il n'existe pas de `relics.hardening.sudo`, et cette absence est délibérée. Les
deux réglages habituellement réclamés — `Defaults use_pty` et un fichier de log
sudo dédié — sont respectivement déjà le défaut amont (sudo ≥ 1.9.14, et de tout
temps sous sudo-rs) et un moins bon marché que le journal où sudo écrit déjà. La
mesure complète et la porte de sortie pour le consommateur qui doit satisfaire le
contrôle à la lettre sont dans
[Conformité ANSSI-BP-028](/stc/fr/reference/anssi-bp-028/).

## Exemple d'utilisation

Reliques individuelles :

```nix
modules = [
  stc.nixosModules.relics-hardening-kernel
  stc.nixosModules.relics-hardening-network
  stc.nixosModules.relics-hardening-filesystem
  stc.nixosModules.relics-hardening-ssh
  stc.nixosModules.relics-hardening-modules
  stc.nixosModules.relics-hardening-scheduler
  stc.nixosModules.relics-hardening-audit
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
  stc.relics.hardening.scheduler.enable = true;
  stc.relics.hardening.audit.enable = true;

  # Le pare-feu est géré séparément — ouvre les ports ici selon tes besoins :
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
```

Machine gaming avec durcissement :

```nix
{
  stc.relics.hardening.kernel.enable = true;

  stc.relics.hardening.filesystem.enable = true;
  stc.relics.hardening.filesystem.gaming = true;  # autorise exec dans /tmp, /var/tmp et /dev/shm
  stc.relics.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D ont besoin de plus que 256M

  stc.relics.hardening.network.enable = true;
  stc.relics.hardening.ssh.enable = true;
}
```

## Le raccourci cogitator-hardening

Pour le cas courant d'activation des sept reliques avec les valeurs par défaut,
utilise [`cogitator-hardening`](/stc/fr/cogitator/hardening/). Une option au lieu de sept :

```nix
modules = [ stc.nixosModules.cogitator-hardening ];

# configuration.nix
{ stc.cogitator.hardening.enable = true; }
```

Le cogitator ne t'empêche pas de régler les options individuelles ensuite —
`stc.relics.hardening.filesystem.tmpSize` et `stc.relics.hardening.ssh.allowedTCPForwarding`
restent configurables.

## Échappatoires opérationnelles ajoutées en v0.18.0

Quatre valeurs que ces reliques épinglaient valent désormais `lib.mkDefault`,
parce que les décliner relève de l'exploitation et non d'un changement de modèle
de menace :

```nix
# Relayer une application graphique distante, ou rebondir par un bastion avec son agent.
stc.relics.hardening.ssh = {
  allowedX11Forwarding = true;
  allowedAgentForwarding = true;
  allowedTunnel = true;
};

# Récupérer les core dumps le temps d'un débogage.
systemd.coredump.enable = true;
```

Les trois interrupteurs de forwarding sont des **options**, et non des valeurs
`mkDefault` : c'est délibéré. Écrits en `lib.mkDefault`, ils entraient en
collision avec les modules amont qui posent le même réglage — le module slurm de
nixpkgs écrit
`services.openssh.settings.X11Forwarding = mkIf cfg.client.enable (mkDefault true)`,
et un client Slurm durci ne se construisait plus. Une option garde la valeur de
la relique déterministe face à l'amont et te laisse quand même une ligne.

:::danger[Réactiver les core dumps expose des secrets, et la limite PAM ne l'empêche pas]
Une version précédente de cette page affirmait que l'entrée
`security.pam.loginLimits` de la relique maintenait le durcissement même avec le
handler réactivé. **C'est faux, pour deux raisons indépendantes :**

- `loginLimits` écrit `/etc/security/limits.conf`, appliqué par `pam_limits` aux
  *sessions de connexion* PAM. Un service systemd n'est jamais passé par là :
  la limite n'a donc jamais borné les dumps d'un démon.
- Activer `systemd-coredump` installe un `core_pattern` en tube, et `core(5)`
  est explicite : *« The RLIMIT_CORE limit is not enforced for core dumps that
  are piped to a program »*. La limite cesse alors de s'appliquer, y compris aux
  sessions de connexion.

Donc avec le handler actif, chaque démon qui plante écrit **tout son espace
d'adressage** — clés privées TLS, jetons de session, secrets déchiffrés — dans
`/var/lib/systemd/coredump`. Active-le délibérément, pour le crash que tu
traques, puis remets-le à `false`.
:::

Ce qui reste épinglé est la revendication réelle de la relique :
`PasswordAuthentication = false`, `KbdInteractiveAuthentication = false` et
`PubkeyAuthentication = true`. Les démoter laisserait un hôte documenté comme
durci accepter de nouveau les mots de passe sans bruit : les contredire arrête
donc toujours ton build. Règle complète dans
[Valeurs par défaut surchargeables](/stc/fr/reference/overridable-defaults/).
