# Ledger — plan: .claude/plans/v0.13.0/ssh-authorized-keys.md

Pre-flight: le Step 2 consomme `cfg.systemAuthorizedKeysOnly`, produite au
Step 1 — nom vérifié identique des deux côtés, et les Steps 4 et 5 citent le
même. Le Step 3 ne consomme que `cfg.allowedTCPForwarding`, qui existe déjà
(`relics/nixos/hardening/ssh.nix:26-30`). Option neuve, aucun renommage,
Gate 3 sans objet.

Ruling (avant toute ligne de code) : deux prémisses de l'issue sont périmées, les
deux mesurées dans le nixpkgs verrouillé.

1. Le `lib.mkForce` sur `authorizedKeysFiles` que l'issue reprend de srvos est
   inutile : `services.openssh.authorizedKeysInHomedir` existe (défaut `true`,
   `sshd.nix:444`) et le passer à `false` rend exactement
   `[ "/etc/ssh/authorized_keys.d/%u" ]`. On prend le bouton amont — et comme
   `authorizedKeysFiles` est un `listOf str`, la liste reste **ouverte aux
   ajouts** d'un consommateur, ce qu'un `mkForce` aurait fermé.
2. Des « trois petits défauts » à adopter, deux sont déjà acquis : `UseDns` vaut
   déjà `false` en amont (`sshd.nix:529`) et `X11Forwarding = false` est déjà posé
   par la relique (`ssh.nix:110`). Aucun code, une ligne ✅ en doc — même
   arbitrage que `pid_max` dans #43.

Ruling: assertion plutôt qu'exclusion automatique à la srvos. Mesuré d'abord que
c'était sûr : `services.{gitea,forgejo,gitlab,gitolite,gerrit}` existent toutes
dans une éval NixOS nue (`…#nixosConfigurations.local-vm.options --apply` →
les cinq à `true`), donc lire `config.services.<forge>.enable` n'expose pas au
piège de l'option inconnue rencontré avec sops-nix en v0.12.0. Arbitrage, selon
la méthode « mesurer le consommateur » : qui active une forge sur un hôte durci
perd l'accès SSH de sa forge au **runtime**, à distance, sans rien de rouge ; un
build qui échoue avec un message nommant l'option coûte une ligne de
configuration. Le build rouge est strictement moins cher que le lockout
silencieux.

Ruling: `StreamLocalBindUnlink = cfg.allowedTCPForwarding` et non `true` nu. La
relique coupe déjà agent-forwarding, tunnels et gateway ports, et
`AllowTcpForwarding` vaut `false` par défaut : sans forwarding il n'y a aucune
socket oubliée à délier, donc un `true` inconditionnel serait du décor. Coût si
faux : nul — quand le forwarding est coupé, le réglage n'a pas d'objet.

Ruling (Step 2, trouvé en relisant le message d'erreur produit) : le message
d'assertion est construit avec un pluriel correct. La première version rendait
« services.gitea and services.gitolite **manages its own** authorized_keys
file ». Un message d'erreur bâclé se lit comme du bruit, et celui-ci est la
seule chose que verra quelqu'un dont le build vient de casser. Deux formes
vérifiées à l'évaluation, singulier et pluriel.

Ruling (Step 4) : le proving utilise **un seul matériel de clé pour deux
utilisateurs**, pas deux paires. Avec deux paires, le refus attendu pourrait
venir d'un algorithme écarté plutôt que du chemin, et l'assert passerait pour
la mauvaise raison. Contrôle posé avant le refus : le fichier planté est
installé avec le bon propriétaire et le bon mode, et comparé octet à octet au
fichier déclaré — donc l'échec ne peut pas être imputé à une fixture cassée.
**Limite résiduelle assumée** : le proving ne contient pas de nœud témoin avec
`systemAuthorizedKeysOnly = false` qui montrerait que le même montage
*fonctionnerait* sans le verrou. Ça demanderait un second nœud (donc un second
VM) dans un proving qui n'en a qu'un ; le rapport coût/preuve n'en valait pas
la peine, et le comportement inverse de l'option est déjà mesuré à
l'évaluation (voir Step 1).

Ruling (Step 4, piège d'outillage) : `ssh` doit être invoqué avec `-n` dans un
nixosTest qui se connecte à lui-même. Sans `-n`, ssh lit le stdin de la console
série et avale le marqueur que le driver y écrit ; ça remonte en
`invalid literal for int() with base 10: ''`, une erreur d'analyse du driver qui
ne ressemble en rien à un problème SSH. Les tests de nixpkgs n'y tombent pas
parce qu'ils vont d'un nœud client vers un nœud serveur. Commenté dans le
proving pour que personne ne retire le drapeau.

## Steps

- **Step 1** — `eab7ca0` — option `systemAuthorizedKeysOnly` (défaut `true`) via
  `services.openssh.authorizedKeysInHomedir`. Trois états mesurés :
  défaut → `[ "/etc/ssh/authorized_keys.d/%u" ]` ; option à `false` →
  `[ "%h/.ssh/authorized_keys" "/etc/ssh/authorized_keys.d/%u" ]` (donc la
  bascule n'est pas une tautologie) ; consommateur ajoutant un chemin →
  `[ "/etc/ssh/forge_keys/%u" "/etc/ssh/authorized_keys.d/%u" ]` (la liste
  fusionne, le verrou tient).
- **Step 2** — `0dcfed4` — assertion des cinq forges. Trois cas vérifiés :
  sans forge → build ; forge + verrou → échec ; forge + opt-out explicite →
  build.
- **Step 3** — `ecdf514` — `StreamLocalBindUnlink = cfg.allowedTCPForwarding`.
  Vérifié dans le `sshd_config` rendu : `no` par défaut, `yes` quand le
  forwarding est autorisé. Le même fichier tranche les deux autres réglages
  demandés par l'issue : `UseDns no` et `X11Forwarding no` y figurent déjà
  sans qu'on écrive une ligne.
- **Step 4** — `09e309b` — proving étendu. `ssh` vers l'utilisateur déclaré
  réussit en 0,89 s, vers l'utilisateur à clé plantée échoue en 0,17 s — un
  refus d'authentification, pas un timeout.
- **Step 5** — `734c428` — doc EN + FR : bloc `:::danger:` (ce qui cesse de
  marcher, la commande de vérification avant switch, garder une seconde voie
  d'accès) et bloc `:::caution:` (la **classe** de logiciels, pas seulement les
  cinq services asserts). Pages de référence ANSSI : l'option est nommée dans
  le paragraphe « hors périmètre BP-028 », aucun `Rxx` inventé.

## Gates

- `just ci` → `all checks passed` + `docs parity OK`.
- `just test` → proving `hardening` vert, avec les trois nouveaux asserts
  réellement exécutés (traces d'exécution dans le journal du build, pas un
  cache : le nœud change, donc l'image de test est reconstruite).
- Les trois schematics évaluent.
- Cas négatif de l'assertion reproduit et son message relu en entier, dans ses
  deux formes grammaticales.
- Banc d'essai VM : non nécessaire ici, contrairement au chantier A. Le
  proving boote un vrai sshd et exerce une authentification réelle, ce qui est
  strictement plus que ce qu'un `vmVariant` aurait montré.
