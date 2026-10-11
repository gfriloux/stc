# Ledger — plan: .claude/plans/v0.12.0/plan.md

Pre-flight: Step 2 consomme les options déclarées au Step 1 —
`stc.relics.vmVariant.{enable,disableZfs,disableImpermanence,disableContainers,rootPassword,skipActivationScripts,maskUnits}`,
noms vérifiés identiques des deux côtés, et le Step 3 (doc) cite les mêmes.
Step 1 consomme `stc.relics.zfs.enable` / `stc.relics.impermanence.enable`, qui
sont produites par d'autres reliques et non par une étape de ce plan — d'où la
garde d'existence ci-dessous. Aucun renommage d'option, Gate 3 sans objet.

Ruling: la définition de `virtualisation.vmVariant` est un **module-fonction**
avec garde `options.stc.relics ? <relique>`, et non l'attrset plat du plan.
Raison mesurée avant d'écrire la relique : `lib.mkIf false` **ne protège pas**
contre une option inconnue (`nix-instantiate` sur un `config = mkIf false
{stc.relics.doesNotExist.enable = true;}` → « The option `stc.relics.doesNotExist'
does not exist »), et `stc.relics.zfs` n'existe que chez un consommateur qui
importe cette relique — la variante VM étendant la liste de modules du host.
Sans la garde, la relique cassait l'évaluation de tout host n'important pas les
deux autres. Le même essai a confirmé qu'un module-fonction est accepté comme
définition de `virtualisation.vmVariant` et que `options ? sops` saute
proprement. Coût si faux : aucun, la garde est strictement plus permissive.

Ruling: `skipActivationScripts` écrit `.text = lib.mkForce ""` et non
`lib.mkForce ""` sur la clé entière. Raison : à la clé entière, le `mkForce`
remplace tout le sous-module et emporte le `deps` du script d'origine ; en ne
forçant que `text`, le nœud **et** ses dépendances survivent, ce qui est le motif
même pour lequel le plan vide le script au lieu de supprimer l'attribut. Coût si
faux : nul, `deps` conservé est un sur-ensemble du comportement voulu.

Ruling: la commande de vérification du Step 2 a été réécrite. Celle du plan
(`builtins.getFlake` + `extendModules` avec seulement l'attrset d'options) aurait
échoué : `schematics/dreadnought` n'importe pas la relique, donc
`stc.relics.vmVariant` n'y existe pas. Remplacée par un `nix eval --apply
--impure` qui injecte explicitement le chemin du module. Défaut de plan, tranché
sans arrêt de chantier. Coût si faux : nul, la preuve obtenue est plus forte.

Ruling: la neutralisation des conteneurs a été prouvée sur un banc
`eval-config.nix` dédié et non sur `dreadnought`, où `vm_containers = []` est une
tautologie (ce schematic ne déclare aucun conteneur). Le banc déclare `app` et
`db` : prod `["app" "db"]` avec et sans la relique, VM `[]`. Le même banc
n'importe **ni** la relique ZFS **ni** impermanence, ce qui prouve au passage la
garde d'existence du premier ruling. Coût si faux : nul.

Ruling: défaut de plan au Step 3 — `npm run astro check` n'existe pas
(`docs/package.json` n'expose que `dev`/`build`/`preview`). Gate réel utilisé :
`just docs-build` (astro build), qui rend les 88 pages dont les deux nouvelles.
Coût si faux : un gate de doc plus faible que prévu sur la vérification des
types, compensé par `just docs-parity` et la construction complète du site.

Step 1: complete (`relics/nixos/vm-variant.nix`, `nix flake check` → all checks passed)
Step 2: complete (`relics/default.nix` ; preuve centrale sur `dreadnought` →
  `prod_identique = true`, `prod_zfs = true` / `vm_zfs = false`,
  `prod_impermanence = true` / `vm_impermanence = false`, `vm_rootpw = "vm"`,
  `vm_hashedpw = null`, `vm_setupsecrets = ""`, `system.build.vm.drvPath` évalue ;
  banc conteneurs → prod `["app" "db"]` / vm `[]`, `vm_hashedpwfile = null`,
  `vm_warnings = []` donc aucun warning amont de mots de passe multiples ;
  les trois schematics évaluent)
Step 3: complete (`docs/.../{en,fr}/relics/vm-variant.md` + les deux `relics/index.md`,
  `just docs-parity` → OK, `just docs-build` → 88 pages, `just ci` → vert,
  `just test` → les trois provings verts, non-régression attendue puisque aucun
  cogitator ne change)
