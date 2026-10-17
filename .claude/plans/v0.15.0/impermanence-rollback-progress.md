# Ledger — plan: .claude/plans/v0.15.0/impermanence-rollback.md

Pre-flight (2026-10-17, avant toute branche) : trois défauts séparés (A : échec
non fatal, B : script sans `set -e`, C : `@blank` re-créé sur racine sale), trois
correctifs distincts. Prémisses toutes mesurées dans le nixpkgs verrouillé —
voir la table du plan.

Ruling (2026-10-17, arbitré par l'utilisateur parmi trois propositions) :
`onRollbackFailure` a pour défaut **`"continue"`**, pas `"emergency"` — le boot
se poursuit comme aujourd'hui et la correction porte entièrement sur la
visibilité de l'échec. Pourquoi : aucune rupture pour un consommateur qui bump
`stc`, et l'arbitrage disponibilité/intégrité pour les profils headless reste
à #69 au lieu d'être préempté ici. Coût si c'est le mauvais choix : un hôte dont
le rollback rate démarre encore sale — mais il le **dit** désormais, et
`"emergency"` est là pour qui veut l'inverse. Une ligne de relique à changer si
on revient dessus.

Pre-flight : dépendance d'ordre — le chantier 1 doit être mergé avant, son
proving est le gate du Step 1 et du Step 3.

Conséquence de la ruling ci-dessus : `provings/dreadnought.nix` **continue de
booter sans aménagement**. Seul son jeu d'unités en échec s'élargit à
`{"stc-grow-pool.service", "stc-impermanence-state.service"}` — le proving qui a
trouvé le défaut est celui qui constate qu'il est réparé.

Ruling (Steps 1-3 fusionnés en un commit) : les trois défauts vivent dans le même
fichier et n'ont qu'un seul gate — le boot du proving. Step 1 a quand même été
vérifié isolément avant les deux autres (ligne de journal « @blank is missing …
becomes the permanent clean reference » observée sur le banc), donc la fusion ne
cache rien. Coût si c'est le mauvais choix : nul, c'est une frontière de commit.
Précédent : le chantier 3-B, groupé pour la même raison.

Step 1 : complete — script durci (`set -euo pipefail`, dataset vérifié avant le
snapshot, `2>/dev/null` masquant retiré, deux marqueurs `/run`). Script rendu lu
en entier par `builtins.readFile` sur l'`ExecStart`, pas supposé.
`nix flake check` → exit 0 ; proving `sarcophagus-kvm` → exit 0, et le journal du
boot 1 porte bien le nouvel avertissement.

Step 2 : complete — `onRollbackFailure` (enum, défaut `"continue"`).
**Vérification négative faite avant d'écrire l'assert** (méthode
[[feedback-eval-guard-method]]) : `unitConfig` du `zfs-rollback` contient
`OnFailure`/`OnFailureJobMode` sous `"emergency"` et **pas** sous `"continue"`,
le défaut étant identique à `"continue"`. L'option n'est donc pas décorative.

Step 3 : complete — `stc-impermanence-state.service` dans le système démarré.
Échoue sur le marqueur d'échec, **avertit seulement** sur le marqueur
`@blank`-créé (créer la référence est normal au premier boot, anormal ensuite, et
la relique ne sait pas distinguer — décision 4).

Step 4 : complete — les deux provings. `dreadnought` boote sans aménagement
(bénéfice du défaut `"continue"`), son jeu d'unités en échec passe à
`{stc-grow-pool, stc-impermanence-state}`, et un sous-test lit le `Result` de
l'unité et son journal. `sarcophagus-kvm` gagne le contre-test : sur le chemin
sain, aucun marqueur, unité verte. `nix build` des deux → exit 0 (63,72 s et
25,39 s).

Observé au passage, et c'est la démonstration du chantier : au boot 1 du banc,
l'avertissement `@blank` remonte **deux fois** — dans le journal d'initrd puis
dans celui du système démarré — et `is-system-running` reste `running`. Un
avertissement, pas un échec. C'est exactement le partage voulu par la décision 3.

Step 5 : complete — doc EN+FR de la relique : l'option dans la table, une section
« When the rollback fails » qui dit que le boot continue par défaut et ce que
coûte `"emergency"` (`emergencyAccess` à `null` = pas de shell), et une section
« If @blank goes missing » qui écrit noir sur blanc la réduction de portée. Lignes
de couverture des provings mises à jour. `docs-parity` → OK, `npm run build` → 90
pages.
