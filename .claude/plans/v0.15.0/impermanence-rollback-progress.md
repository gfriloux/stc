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
