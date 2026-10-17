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
coûte `"emergency"` (`emergencyAccess` à `false` = pas de shell), et une section
« If @blank goes missing » qui écrit noir sur blanc la réduction de portée. Lignes
de couverture des provings mises à jour. `docs-parity` → OK, `npm run build` → 90
pages.

## Revue de clôture par contexte neuf (2026-10-17)

Sous-agent, diff `913557c..HEAD`, Review Focus verbatim. **Aucun Critical** — il a
vérifié sur le script *rendu* (pas la source Nix) qu'aucun chemin sain ne peut
rougir sous `set -euo pipefail` (toute commande faillible est gardée par `||`,
`fail()` n'est appelé qu'en RHS de `||` donc errexit y est suspendu, et le script
sort 0 ssi `zfs rollback` sort 0) ; que `stc-impermanence-state.service` ne peut
pas échouer sur un `/run` vierge ; que le rbind `/run`→`/sysroot/run` est
**inconditionnel** (`initrd.nix:758-772`, hors du `mkIf` voisin) ; que `touch`
est bien dans l'initrd (`coreutils` dans `initrdBin`, `PATH=/bin:/sbin`) ; et que
`OnFailureJobMode = "replace-irreversibly"` avec `DefaultDependencies = "no"` est
la combinaison que systemd emploie lui-même sur `initrd-fs.target`.

**Important 1 — retenu, et c'est une 4ᵉ occurrence du motif « fait faux publié ».**
`boot.initrd.systemd.emergencyAccess` vaut **`false`** par défaut, pas `null`.
J'avais lu la prose de la description amont (« false or null for no emergency
access ») et transcrit la mauvaise valeur, **puis consigné ça comme “mesuré” dans
la table de prémisses** — ce qui est le vrai défaut de méthode ici. Re-mesuré
deux fois (`initrd.nix:348` et `nix eval` sur `options.…default`). Corrigé dans
les 5 endroits : description d'option, doc EN, doc FR, plan, ce ledger. La
*conséquence* annoncée (aucun shell) reste vraie : l'amont calcule
`access = ea != null && !(isBool ea && !ea)`, donc `false` comme `null` verrouille
le compte root.

**Important 2 — retenu.** L'option `"emergency"` n'avait **aucune garde
committée** : le `nix eval` négatif du Step 2 était interactif, pas un gate. Un
refactor supprimant le `lib.optionalAttrs` aurait laissé les huit provings verts
et l'échappatoire décorative. Corrigé par un **nœud d'évaluation seule**
`emergencyvariant` dans `provings/dreadnought.nix`, jamais démarré — il ne peut
pas l'être, son rollback échoue toujours et `emergency` bloquerait le boot. La
garde est double : l'interpolation Nix de `.OnFailure` fait **échouer le build**
du proving si l'attribut disparaît, et un sous-test compare les deux variantes au
runtime, y compris la moitié négative (le défaut ne porte pas `OnFailure`).

**Important 3 — retenu, et c'était une tautologie.** Le marqueur
`@blank`-créé — toute la mitigation du défaut C — n'était asserté nulle part : le
seul assert qui le nomme vérifie son *absence* au boot 2, ce qui passe aussi s'il
n'est jamais écrit. Mesuré par le relecteur : en révoquant le `touch`, l'`echo` et
le premier `if` de l'unité, tout restait vert. Corrigé par un sous-test au boot 1
— le seul boot de la suite où la création a lieu — qui vérifie le marqueur, le
message d'initrd, sa répétition dans le journal du système démarré, et que
l'unité reste **active** (avertissement, pas échec).

**Minor 4 — retenu.** « the only way this unit can say anything at all to
userspace » est faux, et contredit par le dépôt lui-même : `dreadnought` lit le
journal d'initrd de l'unité avec `-u`. Reformulé en « raise a *failure* userspace
will notice ».

**Minor 5 — retenu** (« a four-line unit » pour 13 lignes de script).

**Minor 6 — retenu, et le plus intéressant.** « le boot s'arrête » est
conditionnel : `OnFailure` *démarre* `emergency.target`, il n'annule pas le boot.
Le compte root étant verrouillé, `sulogin` attend indéfiniment — donc un hôte
headless bloque bien — mais quelqu'un devant une console qui appuie sur Entrée
reprend le boot avec la racine sale. Un paragraphe ajouté dans les deux pages :
lire `emergency` comme « un humain doit trancher », pas « cet hôte ne peut pas
démarrer ».

**Minor 8 — retenu** (commentaire) : nommer la branche réellement exercée par
`dreadnought`, à savoir le contrôle du dataset, jamais le `zfs rollback`.

**Minor 7 — corrigé au passage** (assert nu sans message).

**Rien de différé cette fois.** Vérifications après la passe :
`nix flake check` → exit 0, `docs-parity` → OK, `npm run build` → 90 pages,
`nix build` des deux provings → exit 0 (66,40 s et 25,89 s), et les deux nouveaux
sous-tests confirmés dans les logs des dérivations
(« boot 1: creating @blank is announced, twice », « onRollbackFailure actually
changes the unit »).
