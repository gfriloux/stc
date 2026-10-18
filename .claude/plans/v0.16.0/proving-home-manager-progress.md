# Ledger — plan: .claude/plans/v0.16.0/proving-home-manager.md

Pre-flight (2026-10-18, avant toute branche) : chantiers 2 et 3 du lot « les
épreuves, palier 2 ». Un plan pour deux issues (#83, #50), une branche et une PR
par issue — même forme qu'en v0.14.0.

Pre-flight : le mécanisme HM a été **mesuré avant l'écriture du plan**, pas
supposé faisable. Sondes jetables hors arbre, sous le nixpkgs et le
home-manager verrouillés :
  - `inputs.home-manager.nixosModules` = `["default" "home-manager"]` → aucun
    input à ajouter au flake.
  - Un nœud important `home-manager.nixosModules.home-manager` avec
    `home-manager.users.proving.imports = [self.homeModules.cogitator-enginseer]`
    évalue, et `config.systemd.services` gagne exactement `home-manager-proving`
    → l'activation est une unité systemd ordinaire, donc `wait_for_unit`
    s'applique. Idem pour `cogitator-desktop`.
  - `home.activationPackage.drvPath` se force sans erreur unfree pour les trois
    combinaisons (enginseer, desktop, les deux) → **ni l'un ni l'autre n'a besoin
    de `pkgs-unfree`** ; `gaming` reste le seul cas unfree du dépôt.
  - `nix build` des deux clôtures d'activation (enginseer seul, enginseer +
    desktop avec gimp/vlc/zen-browser) : **exit 0 les deux**. Le coût de
    construction est payé, pas spéculatif.
  - `useGlobalPkgs = true` + `useUserPackages = true` changent le `drvPath`
    (`sameClosure = false`) et remplissent `users.users.<u>.packages` → décision 3,
    et les paquets deviennent assertables sous `/etc/profiles/per-user/<u>/bin`.
  - Chemins rendus relevés nommément (fish `config.fish`, `oh-my-posh/dracula.omp.json`,
    `git/config`, `direnv/*`, `bat/config` + thème catppuccin, `systemd/user/gpg-agent.service`
    pour enginseer ; `kitty/kitty.conf` et l'unité ghostty pour desktop, **rien**
    pour zen-browser) → les asserts visent des fichiers nommés, pas un `grep` à
    l'aveugle.
  - **La revendication croisée est vraie et mesurée** : `pinentry.package` vaut
    `pinentry-curses` sur enginseer seul et `pinentry-qt` sur les deux profils ;
    et sur desktop seul `gpg-agent.enable = false` avec **aucune** unité
    `gpg-agent` rendue, alors que `pinentry.package` vaut quand même
    `pinentry-qt`. C'est ce qui impose l'ordre 2 → 3 (décision 2) et ce qui fait
    de #50 autre chose que « gimp est installé ».

Pre-flight : `provings/default.nix` ne passe aujourd'hui que `{inherit self;}` ;
les deux épreuves HM ont besoin d'`inputs`. Changement d'interface local assumé —
les neuf autres gardent `{self}`, les deux formes cohabitent, et la raison
s'écrit dans `provings/default.nix` (step 1).

Pre-flight : aucun fichier de `relics/`, `cogitator/`, `schematics/` ni
`flake.nix` ne doit changer — vérifié contre la liste *Affected Files*.

Pre-flight PF-1 → PF-5 : à exécuter et consigner ici avant le step 1, et les
quatre inconnues de PF-4 à lever avec commande et sortie.

---

<!-- Une ligne par step livré, chaque ruling, chaque mineur différé. -->
