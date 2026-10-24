---
title: Valeurs par défaut surchargeables
description: Quand une relique STC épingle une valeur et quand elle ne fait que la proposer — la règle, ce qui est devenu surchargeable en v0.18.0, et ce qui reste épinglé exprès.
---

Toute valeur qu'une relique ou un cogitator écrit est soit un **défaut** que tu
peux contredire par une définition nue, soit un **épinglage** que tu ne peux pas
contredire. Nix rend cette différence invisible jusqu'à ce qu'elle morde :
contredis un épinglage et le build s'arrête sur
`has conflicting definition values`, en nommant deux fichiers et en suggérant
`lib.mkForce`, sans rien qui t'indique lequel des deux était censé gagner.

Cette page dit lequel est lequel, et pourquoi.

## La règle

> Une valeur est épinglée quand le conflit qu'elle lève est la seule chose qui
> empêche une configuration incohérente d'être construite. C'est un défaut —
> `lib.mkDefault` — dès lors que la désactiver laisse une configuration qui a
> encore du sens.

L'illustration la plus nette est `cogitator-dreadnought`. Il active
`stc.relics.zfs` **et** déclare `fileSystems."/"` avec `fsType = "zfs"`. Coupe la
relique et la configuration s'évalue quand même : ce qui en sort est un hôte dont
la racine est un dataset ZFS sur un système sans support ZFS. Ça se construit, et
ça ne boote pas. Le conflit est la seule chose qui se dresse entre toi et cet
hôte : l'activation de la relique y reste donc épinglée.

Compare avec `cogitator-plasma`, qui active aussi deux reliques. Plasma 6 est ce
que le profil *est* — décline-le et le profil ne définit plus rien, donc il reste
épinglé. Pipewire est un ajout : décline-le et tu as un bureau Plasma cohérent
dont le son est géré ailleurs. C'est donc un défaut, et une ligne l'exprime :

```nix
stc.cogitator.plasma.enable = true;
stc.relics.pipewire.enable = false;   # pas besoin de mkForce
```

## Ce qui est devenu surchargeable en v0.18.0

Chaque entrée ci-dessous était épinglée à priorité normale avant `v0.18.0` et
vaut `lib.mkDefault` à partir de cette version. La valeur effective est
inchangée : une configuration qui ne les pose pas se construit exactement comme
avant — vérifié par identité de `drvPath` sur les trois schematics et les onze
épreuves.

Si tu as contourné l'une d'elles avec `lib.mkForce`, tu peux le retirer.

### Les profils n'imposent plus leurs parties

| Profil | Désormais déclinable |
|---|---|
| `cogitator-hardening` | les six sous-reliques : `stc.relics.hardening.{kernel,network,filesystem,ssh,modules,scheduler}.enable` |
| `cogitator-workstation` | `stc.relics.hardening.{kernel,network,modules}.enable` |
| `cogitator-plasma` | `stc.relics.pipewire.enable` |
| `cogitator-gaming` | `stc.relics.amdGpu.enable`, `stc.relics.pipewire.enable` |
| `cogitator-docker-server` | `stc.relics.docker.socketProxy.enable`, `stc.relics.docker.crowdsec.enable`, `stc.relics.preSwitchChecks.enable` |
| `cogitator-dreadnought`, `cogitator-sarcophagus-{kvm,aws}` | `stc.relics.networking.enable`, `stc.cogitator.hardening.enable` |
| `cogitator-desktop` (Home Manager) | `stc.relics.gui.{kitty,ghostty,zen-browser}.enable` |
| `cogitator-vm` | `nix.optimise.automatic` |

La ligne `docker-server` mérite une phrase à elle seule. Les reliques Docker
**assertent** sur l'image manquante : avant `v0.18.0`, décliner CrowdSec n'était
pas seulement pénible — il fallait fournir à CrowdSec une image que tu n'avais
jamais l'intention de lancer, ou recourir à `mkForce`. Un hôte de jeu sur GPU
Intel ou NVIDIA était dans la même position avec la relique AMD.

Depuis `v0.19.0`, les quatre profils serveur (`docker-server`, `dreadnought`,
`sarcophagus-{kvm,aws}`) activent aussi deux reliques en `mkDefault`, toutes deux
déclinables : `stc.relics.serverSurvivability.enable` et
`stc.relics.nixHousekeeping.enable`. `cogitator-vm` active aussi la seconde ; sa
ligne `nix.optimise.automatic` ci-dessus vit désormais dans cette relique,
toujours comme défaut.

### Réglages de reliques

| Relique | Désormais surchargeable | Pourquoi tu voudrais |
|---|---|---|
| `relics-zfs` | `boot.zfs.forceImportAll` | un pool non-root portant légitimement un hostid étranger — **pose aussi `boot.zfs.forceImportRoot = true`**, sinon l'amont asserte : *« If you enable boot.zfs.forceImportAll, you must also enable boot.zfs.forceImportRoot »* |
| `relics-boot` | `boot.loader.efi.canTouchEfiVariables` | un firmware qui refuse l'écriture des variables EFI ; une installation depuis un chroot. Sans objet sur les deux sarcophages : en tant que constructeurs d'image ils la posent eux-mêmes, et là le profil a le dernier mot |
| `relics-impermanence` | `environment.persistence.<chemin>.hideMounts` | voir les bind mounts en déboguant la persistance |
| `relics-aws` | `services.udisks2.enable` | un hôte qui le veut sciemment. À noter : ce n'est plus la relique qui te bloque — mais sur une image bâtie avec le module `amazon-image` de nixpkgs, ce module écrit `false` à priorité normale, donc une définition nue entre en conflit avec l'**amont** et il te faut `lib.mkForce` là |
| `relics-hardening-kernel` | `systemd.coredump.enable` | réactiver les core dumps le temps d'un débogage — lis d'abord l'avertissement sur la [page des reliques de durcissement](/stc/fr/relics/hardening/) : avec le handler actif, les démons écrivent des secrets et la limite PAM de la relique ne l'empêche **pas** |
| `relics-docker-traefik` | logrotate `compress`, `delaycompress`, `missingok`, `notifempty` | ta propre politique de rétention, ou un collecteur qui veut des fichiers non compressés |
| `cogitator-enginseer` (Home Manager) | tout `programs.micro.settings`, `programs.direnv.silent`, `services.gpg-agent.enableSshSupport`, `catppuccin.autoEnable`, `programs.fzf.historyWidget.command` | goûts d'éditeur ; utiliser gpg-agent comme agent SSH ; thématiser ses outils un par un |

### Réglé par une option STC, pas par une priorité

`relics-hardening-ssh` écrit les quatre interrupteurs de forwarding sshd depuis
ses propres options, à priorité normale — et non en `mkDefault`. C'est le niveau
1 de la règle ci-dessus, et la raison est une mesure : en `mkDefault` ils
entraient en collision avec les modules amont qui écrivent le même réglage (le
module slurm de nixpkgs pose
`services.openssh.settings.X11Forwarding = mkIf cfg.client.enable (mkDefault true)`),
ce qui cassait un client Slurm durci qui se construisait avant. Une option garde
la valeur de STC déterministe face à ce que l'amont décidera de mettre par défaut
à la prochaine release :

```nix
stc.relics.hardening.ssh = {
  allowedX11Forwarding = true;     # relayer une application graphique distante
  allowedAgentForwarding = true;   # rebondir par un bastion avec son agent
  allowedTCPForwarding = true;     # préexistante
  allowedTunnel = true;
};
```

## Ce qui reste épinglé, et pourquoi

Ce n'est pas un backlog. Chacun de ces cas est une décision, et la contredire
*doit* arrêter ton build :

- **Une relique dont les déclarations du profil dépendent** — `stc.relics.zfs` et
  `stc.relics.impermanence` dans les profils ZFS, `stc.relics.aws` dans les
  profils EC2, `stc.relics.docker.traefik` dans `docker-server`. Le profil écrit
  la disposition des systèmes de fichiers, le périphérique de boot ou le câblage
  du proxy qui les supposent.
- **Le sujet du profil** — `stc.relics.plasma6` dans `cogitator-plasma`. Le
  décliner, c'est vouloir un autre profil, pas celui-ci moins son sujet.
- **Ce que la relique vend** — `services.pipewire.enable` dans la relique
  Pipewire, `PasswordAuthentication = false` et `PubkeyAuthentication = true`
  dans la relique de durcissement SSH. L'authentification par clés en
  particulier : la démoter laisserait un hôte documenté comme durci accepter de
  nouveau les mots de passe, en silence.
- **Les exigences mécaniques** — `boot.initrd.systemd.enable` pour le rollback
  d'impermanence (l'unité ne peut pas exister dans un initrd scripté),
  `neededForBoot` sur le dataset de persistance.

## Le garde qui maintient cette page vraie

`just option-priorities` (inclus dans `just ci`) lit
`scripts/option-priorities.tsv` et échoue sur deux choses :

1. **Une priorité non enregistrée.** Chaque fichier de `relics/` et
   `cogitator/` qui écrit `lib.mkDefault`, `lib.mkForce` ou `lib.mkOverride` a
   une ligne avec le compte exact et une raison. En ajouter une sans
   l'enregistrer arrête la CI : une priorité est une décision, et une décision
   non enregistrée est une décision prise en secret.
2. **Une collision avec un défaut amont.** Pour chaque option tierce que le
   registre dit écrite en `mkDefault` par STC, le nixpkgs et le home-manager
   verrouillés sont fouillés à la recherche d'un module qui écrit la même option,
   aussi en `mkDefault`. Deux défauts contradictoires sont une erreur de build
   *chez toi*, donc chaque hit doit être inscrit en liste d'exception avec la
   raison mesurée qui le rend inoffensif.

Ce garde existe parce que la règle ci-dessus était écrite et a quand même raté
quelque chose. `v0.18.0` a démoté `services.openssh.settings.X11Forwarding` en
`mkDefault` ; le module slurm de nixpkgs écrit le même réglage en
`mkIf cfg.client.enable (mkDefault true)`, et un client Slurm durci qui se
construisait à la version précédente a cessé de s'évaluer. Rien ne l'a attrapé,
parce que rien ne le mesurait.

Le garde a trouvé un second cas de la même classe à sa première exécution, plus
ancien que ce chantier : `networking.useDHCP` en `mkDefault true` dans la relique
networking contre le `mkDefault false` de `networking.ifstate`. C'est pourquoi le
DHCP est désormais `stc.relics.networking.dhcp`, une option à priorité normale.

**Angle mort connu, dit plutôt que caché :** la recherche amont matche le chemin
complet d'une option et ses deux derniers composants. Un module qui n'écrit
qu'une feuille nue dans un bloc imbriqué peut encore passer. Matcher les feuilles
nues a été essayé puis abandonné — `command`, `package` et `enable` touchent la
moitié de nixpkgs, et un garde qui crie au loup finit désactivé.

## Le vérifier toi-même

Tu n'as pas à croire cette page sur parole. Pose la valeur que tu veux et regarde
si la configuration s'évalue :

```bash
nix eval .#nixosConfigurations.<hôte>.config.system.build.toplevel.drvPath
```

Une valeur épinglée échoue sur `has conflicting definition values` et nomme le
fichier qui l'a écrite. Un défaut passe. Et pour confirmer qu'une relique a
réellement disparu et pas seulement son option, lis quelque chose que seule cette
relique écrit — pour la relique Pipewire, `security.rtkit.enable`, puisque le
module Plasma de nixpkgs active Pipewire de son côté et que ses unités survivent
au déclin de la relique.

L'audit complet, y compris les 93 valeurs délibérément laissées épinglées et les
mesures derrière chaque verdict, est dans
l'[issue #86](https://github.com/gfriloux/stc/issues/86) et dans
`.claude/plans/v0.18.0/triage.md` du dépôt.
