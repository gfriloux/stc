# Ledger — plan: .claude/plans/v0.10.0/plan.md

Pre-flight: Step 2 consomme les options déclarées au Step 1 — noms vérifiés,
`stc.relics.hardening.scheduler.{enable,allowedUsers}` des deux côtés. Step 3
consomme `services.cron.enable` / `services.atd.enable`, qui sont des options
amont et non produites par une étape antérieure. Aucun renommage d'option dans
ce chantier, donc Gate 3 sans objet.

Ruling: un seul commit pour les quatre étapes — CLAUDE.md impose la doc dans le
même changement qu'un changement structurel et le proving dans le même
changement que la revendication, ce qui interdit de les isoler ; précédent des
trois dernières reliques (`5fa14e4`, `109b4f0`, `dbd1f1c`) — coût si faux :
un `git rebase -i` pour redécouper avant le merge.

Ruling: la relique se justifie au mérite et non par le référentiel — aucune
règle ANSSI-BP-028 ne couvre l'accès aux ordonnanceurs, et STC ne revendique
pas CIS (#41). L'argument porteur est l'auto-activation
`services.cron.enable = mkDefault (allFiles != [])`, qui peut livrer un cron
ouvert à tous les utilisateurs locaux à un consommateur qui ne l'a pas demandé.
Coût si faux : la relique est du poids mort inerte, retirable sans casser personne
puisque son `config` est entièrement gardé par `mkIf services.<x>.enable`.

Step 1: complete (`relics/nixos/hardening/scheduler.nix`, `nix flake check` → OK)
Step 1: Ruling: `allowedUsers = []` est refusé par une `assertion` plutôt que
  toléré — une liste vide produit un fichier d'autorisation vide, que cron lit
  comme « personne, pas même root », soit un verrouillage total déguisé en faute
  de frappe. Coût si faux : un consommateur qui voudrait réellement verrouiller
  tout le monde doit poser `boot`/`systemd` lui-même au lieu d'utiliser la
  relique — cas non remonté.
Step 2: complete (`relics/default.nix`, `cogitator/nixos/hardening.nix`,
  `nix flake check` → OK ; `cron.enable`/`atd.enable` restés `false` sur
  `local-vm` et `aws-ami` → la relique n'active rien)
Step 2: Ruling: le nouveau fichier doit être `git add`é avant tout
  `nix eval ./schematics/...` — les schematics sont des flakes séparés qui
  référencent le dépôt par git, donc un fichier non suivi est invisible et
  l'évaluation échoue avec un message qui demande précisément ce `git add`.
  Aucun impact sur le livrable, c'est une mécanique de vérification.
Step 3: complete (`provings/hardening.nix`, `just test` → 3 provings verts).
  Asserts comportementaux retenus en plus du contenu des fichiers : cron a
  journalisé `(schedtest) AUTH (crontab command not allowed)`, `at` a refusé le
  même utilisateur, et root conserve l'aller-retour `crontab -`/`crontab -l` et
  `at`/`atq`. `wait_for_unit("atd.service")` couvre le Review Focus #2 : la
  friction `environment.etc` / `install -dm755` sur `/etc/at` n'empêche pas atd
  de démarrer.
Step 3: Ruling: la détection du refus `crontab` matche le message
  (`"not allowed"`) et pas seulement le code de retour — `crontab -l` sort aussi
  non-zéro pour un utilisateur *autorisé* sans crontab, donc un assert sur le
  seul code de retour aurait passé même relique désactivée. Coût si faux : un
  changement de formulation en amont casse l'assert, ce qui est le bon sens de
  l'échec (visible, pas silencieux).
Step 4: complete (12 fichiers docs EN+FR ; `just docs-parity` → OK,
  `just docs-build` → 86 pages, `[build] Complete!`)
Final: Gates: `just ci` → all checks passed + docs parity OK ; `just test` → vert ;
  `nix eval` des deux artefacts de schematic → drvPath OK ; grep des références
  internes → seuls les faux positifs préexistants (`stc.nixosModules.*` dans les
  flakes de schematics, labels `stc.docker/health-watch`).
Final: minor (deferred): `cogitator-hardening` n'a pas de ligne dans la matrice
  ANSSI pour la relique scheduler côté tableau — le choix a été une section de
  prose, puisqu'il n'y a aucune règle BP-028 à mettre dans la colonne « Rule ».
