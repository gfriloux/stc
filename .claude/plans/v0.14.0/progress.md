# Ledger — plan: .claude/plans/v0.14.0/plan.md

Pre-flight: les quatre paires proving → registre (1.1→1.2, 2.1→2.2, 3.2→3.3,
4.2→4.3) exportent toutes la même forme `{self}: {name; nodes; testScript;}` et
sont toutes importées par `import ./<nom>.nix {inherit self;}` — contrat vérifié
contre les trois provings existants. Paire 3.1→3.3 : le nom `pkgs-unfree` est
celui du `let` du registre, écrit à l'identique dans la ligne `gaming` (et
emprunté à `forge/default.nix`, qui l'épelle pareil). Paire 4.1→4.2 : le nœud
dreadnought ne doit porter **aucune** définition de
`systemd.services."serial-getty@ttyS0"` — c'est tout l'objet du Step 4.1. Aucune
option nouvelle, aucun renommage : Gate 3 sans objet.

Ruling (avant toute ligne de code) : les quatre cogitators ont été sondés en
évaluation, chacun dans un `runNixOSTest` jetable, **avant** d'écrire le plan.
Deux surprises, qui ont changé le plan :

1. `cogitator-gaming` n'évalue pas du tout — `steam` est unfree et le `pkgs` de
   `perSystem` ne l'autorise pas. Les deux voies « locales » sont mesurées
   fermées : `nixpkgs.config.allowUnfree` dans le nœud donne
   `nixpkgs.config is set to read-only`, et `node.pkgs` est déjà défini par
   `runNixOSTest` lui-même (`node.pkgs is defined multiple times`). Seul
   `pkgsUnfree.testers.runNixOSTest` passe — c'est exactement le patron
   `pkgs-unfree` que `forge/default.nix` emploie pour Terraform (BSL), scopé à
   la ligne qui en a besoin.
2. `cogitator-dreadnought` échoue deux fois de suite : d'abord
   `ZFS requires networking.hostId to be set` (le nœud le pose, comme les
   schematics), ensuite un conflit dur sur `systemd.services."serial-getty@ttyS0"`
   — `relics/nixos/aws.nix:82` pose `true` à priorité normale, le socle de test
   pose `false` à la même priorité. Conséquence qui dépasse le test : **aucun
   consommateur de la relique AWS ne peut désactiver ce getty sans `mkForce`**.

Ruling (arbitré avec l'utilisateur, 2026-10-17) : la cause racine du point 2 est
la priorité dans la relique, pas le test. On corrige `relics/nixos/aws.nix` en
`lib.mkDefault true` et le proving ne porte aucun override. Un `mkForce` dans le
test aurait masqué le défaut. Garde-fou : la valeur doit rester `true` pour un
consommateur qui ne change rien, et les `drvPath` des schematics doivent être
identiques avant/après — c'est la vérification du Step 4.1.

Ruling (arbitré avec l'utilisateur, 2026-10-17) : un seul plan et un seul ledger
pour les quatre chantiers, mais une branche, une PR et un merge par issue. Les
quatre provings partagent une méthode unique et un même jeu de prémisses
mesurées ; quatre plan files les auraient recopiées quatre fois. Ce qui reste
interdit (mélanger deux issues dans une branche) ne l'est pas.

Ruling (portée, écrit avant le code pour ne pas être découvert comme un échec) :
mesuré que le module qemu-vm remplace `fileSystems` **et**
`boot.loader.grub.device` dans le nœud dreadnought (`/` + `/nix/.ro-store` +
`/nix/.rw-store` + `/nix/store` + `/tmp/shared` + `/tmp/xchg`, et
`/dev/disk/by-id/virtio-root`), et que le socle de test désactive `timesyncd` et
les noms d'interfaces prévisibles. Donc import de pool, montage des datasets,
device EBS, endpoint NTP AWS et résolveurs Quad9 sont hors de portée du proving —
pour des raisons de framework, pas de code. Ils vont en note de portée, avec
renvoi au vrai banc (le qcow2 de `schematics/local-vm`, celui qui a servi à #70).
Un assert sur une valeur posée par le framework ne prouve rien : on ne les écrit
pas.

---

## Steps

### Chantier 1 — #48, proving `vm` (branche `test/proving-vm`)

- **Step 1.1 — `provings/vm.nix`.** Deux nœuds (`machine` aux défauts,
  `dockervm` avec `docker.enable = true`), 7 subtests. Valeurs attendues toutes
  mesurées avant d'être écrites : shell `fish-4.9.3`, groupes `["wheel"]` puis
  `["wheel" "docker"]`, `OnCalendar=weekly`, `--delete-older-than 5d`,
  `experimental-features = nix-command flakes`.
  Vérif : `nix build .#legacyPackages.x86_64-linux.provings.vm -L` → `exit=0`,
  script de test en 27,7 s.
- **Step 1.2 — registre + recette.** `vm` dans `provings/default.nix` **et** dans
  la recette `test` du `Justfile` (la deuxième moitié est celle qu'on oublie, et
  sans elle le vert est faux).
- **Step 5 (part 1) — doc EN + FR.** Ligne de couverture `vm`, et correction de
  la procédure « Adding a proving » : elle listait 3 étapes et sautait la recette
  `Justfile`, que `CLAUDE.md` et le Gate 5 exigent. `just docs-parity` ✅.

Ruling (trouvé au premier build, cause racine avant correctif) : l'assert
`machine.wait_for_unit("linger-users.service")` ne pouvait structurellement pas
passer. Mesuré dans `nixos/modules/config/users-groups.nix:905-951` : l'unité est
un `Type = "oneshot"` **sans** `RemainAfterExit`, tirée par `multi-user.target` —
donc au moment où le script interroge, elle a déjà fini et elle est
`inactive (dead)`, état que `wait_for_unit` refuse par définition. Ce n'était pas
un défaut du produit mais une mauvaise primitive d'attente de ma part.
Remplacé par `systemctl show -p Result --value linger-users.service` → `success`
**plus** la présence du marqueur `/var/lib/systemd/linger/admin` : on prouve que
le mécanisme a tourné *et* qu'il a laissé sa trace, là où un simple `test -f`
aurait pu passer sur un fichier posé par autre chose. Première règle appliquée :
une seule tentative, après diagnostic, pas trois essais.

Note de méthode (coûtée une fois, à ne pas repayer) : `nix build` sur un flake
git refuse un fichier **non suivi** (`Path 'provings/vm.nix' … is not tracked by
Git`). Un `git add` suffit — c'est aussi ce qui permet de vérifier avant de
commiter, donc avant toute commande signée.
