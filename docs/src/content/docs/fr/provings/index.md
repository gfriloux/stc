---
title: Épreuves
description: nixosTests internes qui bootent une VM et vérifient qu'un cogitator se comporte comme promis.
sidebar:
  order: 0
---

Une **épreuve** (proving) est un test de comportement : un `nixosTest` qui boote
une VM avec un cogitator activé et vérifie qu'il fait réellement ce qu'il
prétend — sysctls effectifs, services configurés comme voulu, etc. Là où
`nix flake check` et les Purity Seals prouvent qu'un flake *évalue*, les épreuves
prouvent qu'un système *fonctionne*. C'est le Rite of Proving du machine spirit.

Les épreuves sont une **QA interne de STC**. Ce n'est pas une API destinée aux
consommateurs — ils ne les importent jamais.

## Hors du gate, volontairement

Les épreuves sont exposées sous `legacyPackages.<system>.provings.*`, un arbre
d'outputs que `nix flake check` **ignore délibérément**. Elles ne font donc
**pas partie du gate `just ci`** : un test de VM est lourd, et le gate CI reste
rapide et statique.

- On les lance à la main : `just test` (chaque épreuve builde et exécute sa VM).
- Linux uniquement (`x86_64-linux` / `aarch64-linux`) — l'attribut est vide ailleurs.
- Builder : `pkgs.testers.runNixOSTest`.

À ne pas confondre avec `forge/purity-seals/`, qui produit des *builders de checks*
réutilisables par les flakes **consommateurs**. Les épreuves testent STC ; elles
ne s'exportent pas.

## Lancer une épreuve

```bash
just test
# ou, directement :
nix build .#legacyPackages.x86_64-linux.provings.hardening -L --no-write-lock-file
```

## Couverture

| Épreuve | Cogitator testé | Ce qu'elle vérifie |
|---------|-----------------|--------------------|
| `hardening` | `cogitator-hardening` | Durcissement sysctl kernel et réseau effectif ; SSH par clés uniquement, login root refusé |
| `docker-server` | `cogitator-docker-server` | Les unités des conteneurs portent leur image épinglée et les flags de healthcheck ; les réseaux docker, le hook notify `OnFailure` et les timers de health-watch sont câblés ; la config statique Traefik est rendue avec le plugin bouncer CrowdSec et l'endpoint socket-proxy |
| `workstation` | `cogitator-workstation` | Le profil câble ses trois concerns : le socle de durcissement (sysctl kernel/réseau, blacklist de modules) est effectif, le `pcscd` YubiKey est présent, et l'unité display-manager du bureau existe |

## Ajouter une épreuve

1. Créer `provings/<nom>.nix` — une fonction `{self}: { name; nodes; testScript; }`.
   Le nœud importe le vrai module du flake via `self.nixosModules.cogitator-<nom>`.
2. La câbler dans `provings/default.nix` sous `legacyPackages.provings.<nom>`.
3. Ajouter une ligne au tableau de couverture ci-dessus (et son miroir anglais).

## Limite de périmètre — durcissement des montages

L'épreuve `hardening` ne vérifie **pas** les options de montage
(`/tmp` + `/dev/shm` en `noexec`, `/proc` en `hidepid=2`). Le relic les délivre
via `fileSystems`, mais le module qemu-vm de nixosTest remplace tout l'attrset
`fileSystems` par `mkVMOverride` (priorité 10), qui écrase le `mkForce`
(priorité 50) du relic. Ces montages n'existent jamais dans la VM de test : une
vérification à l'exécution échouerait pour des raisons de framework, pas réelles.
Le durcissement à base de sysctl n'est pas affecté et est bien vérifié.

## Limite de périmètre — docker-server vérifie le câblage, pas les conteneurs

L'épreuve `docker-server` vérifie le **câblage** généré par les reliques, pas des
conteneurs démarrés. Une VM nixosTest est isolée du réseau, donc `docker pull` ne
peut pas aboutir et les services de conteneurs ne montent jamais. C'est
volontaire : STC possède le câblage réutilisable, pas le cycle de vie des images.
L'épreuve fournit des images factices (jamais tirées) et inspecte les fichiers
d'unités générés avec `systemctl cat`, qui les lit depuis le disque quel que soit
l'état d'exécution ; le démarrage des conteneurs n'est pas attendu.
