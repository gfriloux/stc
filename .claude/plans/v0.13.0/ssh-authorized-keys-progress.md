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

## Steps

<!-- une ligne par étape terminée : Step N — <commit> — <ce qui a été mesuré> -->
