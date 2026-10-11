# Ledger — plan: .claude/plans/v0.12.0/pre-switch-checks.md

Pre-flight: Step 2 consomme les options déclarées au Step 1 —
`stc.relics.preSwitchChecks.{enable,hostnameGuard,closureDiff}`, noms vérifiés
identiques des deux côtés ; Step 3 consomme `enable` via le cogitator du Step 2,
et Step 4 (doc) cite les mêmes. Step 1 consomme `config.networking.hostName` et
`pkgs.dix`, qui sont amont et non produits par une étape de ce plan. Aucun
renommage d'option, Gate 3 sans objet.

Ruling: le fragment du garde-fou s'appelle `stcAbortWrongHost` et non
`stcHostnameGuard`. Découvert en lisant le script généré avant d'aller plus loin :
amont le rend par `lib.mapAttrsToList`, donc les fragments s'exécutent dans
l'ordre des noms d'attributs — « stcClosureDiff » passait **avant** le garde-fou,
donc un déploiement sur le mauvais host affichait d'abord le diff de deux closures
sans rapport, poussant le message d'abandon hors de l'écran. Le message d'abandon
est la seule chose qui dit à l'opérateur ce qui s'est passé. Ordre vérifié après
coup sur le script construit : `stcAbortWrongHost` (l. 8), `stcClosureDiff`
(l. 44), `switchInhibitors` (l. 73). Un commentaire sur place interdit de renommer
sans y penser. Coût si faux : nul, le nom n'est pas une API.

Ruling: la commande de vérification du Step 1 a été remplacée. Celle du plan
(`nix eval` de `system.preSwitchChecksScript`) **ne prouvait rien** : shellcheck
tourne au *build* de `writeShellApplication`, pas à l'évaluation, donc un eval
réussi sur un script non quoté serait passé pour vert. Remplacée par un banc
`runCommand` qui copie le script dans sa sortie, ce qui réalise la dérivation et
fait donc tourner shellcheck, dans les trois combinaisons d'options. Les trois
construisent. Défaut de plan, tranché sans arrêt de chantier.

Ruling: le nœud du proving pose `system.switch.enable = true`. Cause racine lue
dans nixpkgs après un échec en exit 127, pas devinée :
`nixos/lib/testing/nixos-test-base.nix:34` met `system.switch.enable = mkDefault
false` dans tous les tests (optimisation Hydra — « Don't pull in
switch-to-configuration by default »), donc
`/run/current-system/bin/switch-to-configuration` n'existait pas et les subtests
n'avaient rien à exécuter. Commentaire sur place. Coût si faux : un proving qui
passe sans rien prouver, ce qui est pire que rouge.

Ruling: le cas FQDN est exercé **au runtime** et non par `networking.domain`
comme le disait le plan. Vérifié dans nixpkgs
(`nixos/modules/tasks/network-interfaces.nix:1812` : `environment.etc.hostname =
mkIf (cfg.hostName != "") { text = cfg.hostName + "\n"; }`) : seul le nom court
est écrit, donc déclarer un domaine **ne rend pas** le hostname noyau FQDN et le
subtest aurait été une tautologie. Le proving écrit la forme FQDN dans
`/proc/sys/kernel/hostname`, ce qui est de toute façon le vrai scénario (nom
écrasé par DHCP ou cloud-init). Prémisse du plan corrigée.

Ruling: `testScript` devient une fonction `{nodes, ...}:` pour atteindre
`system.preSwitchChecksScript`. Type vérifié avant d'écrire :
`coercedTo lines const (functionTo lines)` avec
`apply = v: args: v (intersectAttrs (functionArgs v) args)`
(`nixos/lib/testing/testScript.nix:15-18`). Coût si faux : nul.

Correction hors ruling: un commentaire du proving justifiait l'écriture dans
`/proc` par « hostname(1) n'est pas dans un closure minimal ». C'est **faux** —
`pkgs.hostname` est dans `environment.corePackages`
(`network-interfaces.nix:1817`). Le commentaire a été réécrit avec la vraie
raison (c'est la valeur que le garde-fou lit, donc le subtest ne dépend pas de
l'état de hostnamed) plutôt que laissé en place.

Step 1: complete (`relics/nixos/pre-switch-checks.nix`, `nix flake check` → all
  checks passed ; les trois combinaisons d'options construisent leur script, donc
  shellcheck est vert sur chacune)
Step 2: complete (`relics/default.nix`, `cogitator/nixos/docker-server.nix` ;
  `local-vm` ne porte que `["switchInhibitors"]` — aucune contamination hors du
  cogitator ; `aws-ami` et `dreadnought` rendent les mêmes drvPath qu'avant le
  chantier)
Step 3: complete (`provings/docker-server.nix` → `just test` vert, cinq subtests :
  `/run/booted-system` présent donc le garde-fou n'est pas court-circuité ;
  `check` passe sur le bon host ; il passe aussi avec un FQDN au runtime ; il
  **échoue** sur `other-machine` et le message nomme `'machine'` et
  `NIXOS_NO_CHECK=1` ; `NIXOS_NO_CHECK=1` repasse ; et `dix` échoue pour de vrai
  sur un closure inexistant — « new profile path does not exist » dans le log —
  sans faire échouer le script)
Step 4: complete (`docs/.../{en,fr}/relics/pre-switch-checks.md`, les deux
  `relics/index.md`, les deux `cogitator/docker-server.md` ; `just docs-parity` →
  OK, `just docs-build` → 90 pages, `just ci` → vert, `just test` → les trois
  provings verts)
