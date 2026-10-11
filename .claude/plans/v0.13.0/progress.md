# Ledger — plan: .claude/plans/v0.13.0/plan.md

Pre-flight: aucune étape de ce plan ne produit d'option consommée par une autre
— le chantier écrit `boot.zfs.forceImportRoot` (option amont) et de la doc. Les
Steps 3 et 4 citent la même valeur que le Step 2 (`false` via `lib.mkDefault`),
vérifié identique des deux côtés. Aucun renommage d'option, Gate 3 sans objet.

Ruling (avant toute ligne de code) : les prémisses des quatre décisions du plan
sont mesurées, pas déduites — le tableau *Prémisses vérifiées* porte la commande
ou le fichier:ligne de chacune. Les trois mesures qui ont changé le contenu du
plan par rapport à l'issue :

1. L'amont bascule à `false` au `stateVersion` 26.11 et **warne** sur son propre
   défaut `true` ; le `true` explicite de STC éteint ce signal. D'où « `mkDefault
   false` » et non « supprimer la ligne » : sans définition, tout consommateur en
   24.11 hérite `true` **plus** le warning.
2. `8425e349` est le `hostId` de l'ISO (`profiles/base.nix:72`). Reprendre la
   route srvos, c'est faire porter à chaque hôte STC l'identité de
   l'installateur — et rouvrir la faille par un autre bout. Refusé.
3. disko ne fait **pas** `zpool export` au build d'image
   (`make-disk-image.nix:171` : `umount -Rv` seul) alors que son `_unmount` le
   fait (`types/zpool.nix:424`), câblé uniquement dans le script autonome. Donc
   « est-ce que l'image importe sans `-f` ? » n'est pas décidable sur dossier :
   c'est le gate du Step 1, avec les deux branches arbitrées d'avance.

Ruling: le proving ne couvrira pas ce chantier, et c'est écrit ici pour que
personne ne cherche l'assert manquant. Le module qemu-vm des nixosTests remplace
`fileSystems` en `mkVMOverride`, il n'y a aucun pool à importer dans un proving —
même raison que la note de périmètre en tête de `provings/hardening.nix`. Le
`vmVariant` ne sert pas non plus : `disableZfs` vaut `true` par défaut, c'est-à-dire
qu'il *retire* précisément l'import forcé qu'on veut observer. La preuve de ce
chantier est le boot du qcow2 `local-vm` (Step 1), à refaire après le commit.

Ruling (trouvé en préparant la mesure du Step 1) : le `true` de la relique était
posé à **priorité normale**, donc un consommateur ne pouvait pas le ramener à
`false` avec une définition nue — il lui fallait `lib.mkForce` (constaté en
tentant la surcharge : « Definition values: … zfs.nix: true / flake.nix: false …
Use `lib.mkForce` or `lib.mkDefault` »). Le défaut n'était donc pas seulement
dangereux, il était non surchargeable proprement. Le `mkDefault false` corrige
les deux d'un coup ; c'est écrit dans le commentaire du module et dans la doc.

Ruling: l'observable du Step 1 a été changé en cours de route. Le plan disait
« SSH répond ». L'image n'a **pas** de console série (`boot.kernelParams` =
`nohibernate root=fstab loglevel=4 lsm=…`, aucun `console=ttyS0`), donc
`-serial file:` écrit un fichier vide et un échec serait indiscernable d'un
boot lent. Méthode retenue, réutilisable : QEMU `-display none` + moniteur sur
socket Unix court (le chemin du scratchpad dépasse la limite de 108 octets des
sockets Unix) + `screendump` à intervalles, PPM converti en PNG et lu. La
capture à 45 s montre `local-vm login:`, celle à 180 s aussi.

## Steps

- **Step 1** — mesure, aucun commit — **le pool importe sans `-f`.** Image
  construite avec `boot.zfs.forceImportRoot = lib.mkForce false` (surcharge
  temporaire, retirée depuis), bootée en QEMU `snapshot=on` : invite
  `local-vm login:` atteinte. Confirmé côté éval sur l'image qui a booté :
  `boot.initrd.systemd.services."zfs-import-vmpool".environment` = `{ ZFS_FORCE = ""; }`,
  et le script fait `zpool import -d /dev -N  vmpool`. **Branche 1 de la
  décision 4** : `mkDefault false` dans la relique, aucune exception pour les
  cogitators `sarcophagus-*`.
- **Step 2** — `2db9685` — `forceImportRoot = lib.mkDefault false` + commentaire
  portant les quatre décisions. Mesuré après : `false` sur les trois schematics,
  et zéro ligne `forceImportRoot` dans `config.warnings` de `local-vm`.
- **Step 3** — `7a23266` — warning `hostId` de `schematics/local-vm` reformulé ;
  il affirmait « zfs.nix forces import, which would hide the collision », ce qui
  devenait l'inverse de la vérité.
- **Step 4** — `91da2f4` — doc EN + FR : ce que protège l'import non forcé, le
  refus du `hostId` partagé, les deux échappatoires (`zfs_force=1` ponctuel,
  `forceImportRoot = true` permanent sans `mkForce`), le conflit
  `mkDefault`/`mkDefault` mesuré, le cas `nixos-anywhere`, et la bascule amont à
  26.11.

## Gates

- `just ci` → `all checks passed` + `docs parity OK`.
- Les trois schematics évaluent (`qcow2`, `awsImage`, `toplevel`).
- **Le boot n'a pas eu à être refait après le commit** : le `drvPath` du qcow2
  après Step 4 est `qcqapln9bb8519niqb2prcphmlan2wy9-nixos-disk-image.drv`,
  exactement la dérivation construite et bootée au Step 1. L'artefact mesuré
  *est* celui que produit le code commité.
- `just test` → exit 0, mais **par cache** : aucun proving ne dépend de
  `relics-zfs`, rien n'a été reconstruit. À lire comme « pas de régression »,
  pas comme « ZFS est couvert » (cf. ruling ci-dessus).

## Fausse piste, instruite et close

Ce ledger a d'abord consigné que le port 22 redirigé « n'a jamais répondu » sur
deux boots et que le flux `just run` + `just ssh` était « possiblement cassé ».
**C'est faux, et la cause est la sonde, pas le schematic.**

La sonde faisait `timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222 && head -c 60 <&3'`.
Une bannière SSH fait 22 octets : `head -c 60` attendait les 38 manquants, le
`timeout` le tuait avant tout affichage, et la capture repartait vide. Faux
négatif à chaque tir.

Mesuré, deux formes de sonde sur la même VM au même instant :

```
A : timeout 3 … head -c 60  → []                       (la sonde d'origine)
B : timeout 3 … head -n 1   → [SSH-2.0-OpenSSH_10.5]
```

Et le guest, interrogé par sa console série (image reconstruite avec
`console=ttyS0,115200` en surcharge temporaire, puis retirée) : `systemctl
is-system-running` → `running`, aucune unité en échec, `sshd` actif et
`LISTEN 0.0.0.0:22` + `[::]:22`, `ens3 UP 10.0.2.15/24` avec un bail DHCP
obtenu en 6 s. Une sonde Python correcte depuis l'hôte reçoit
`SSH-2.0-OpenSSH_10.5`.

**Aucune issue à ouvrir**, et aucun des commits récents du chemin de durcissement
n'est en cause. Leçon consignée parce qu'elle se reproduira : avant de déclarer
un système cassé, prouver que l'instrument fonctionne — ici il suffisait d'une
seconde forme de sonde, trente secondes de travail contre une fausse piste
durable dans un document mergé.
