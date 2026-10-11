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

## Steps

<!-- une ligne par étape terminée : Step N — <commit> — <ce qui a été mesuré> -->
