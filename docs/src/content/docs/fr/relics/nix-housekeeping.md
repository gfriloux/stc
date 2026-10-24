---
title: Entretien de Nix
description: Un hôte qui dure borne seul son store Nix et son journal.
---

**Module :** `stc.nixosModules.relics-nix-housekeeping`

Par défaut, NixOS laisse le store Nix et le journal grossir jusqu'à remplir le
disque. Sur un hôte qui dure, personne ne surveille le disque. La relique borne
donc les deux :

| Sujet | NixOS d'origine | Ce que fait la relique |
|---|---|---|
| GC planifié | Coupé | Hebdomadaire, supprime les générations de plus de 30 jours |
| Disque plein pendant un build | Rien jusqu'à `No space left on device` | Sous 5 Gio libres, Nix collecte jusqu'à libérer 15 Gio |
| Déduplication du store | Coupée | Timer hebdomadaire (`nix.optimise.automatic`) |
| Builds face aux services | Même priorité CPU, IO et OOM | Les builds cèdent : CPU `batch`, IO `best-effort` 7, `OOMScoreAdjust=250` |
| Journal | 10 % du système de fichiers (4G au plus), sans limite de durée | 500M, un mois |

Activée par défaut (`lib.mkDefault`) par
[docker-server](/stc/fr/cogitator/docker-server/),
[dreadnought](/stc/fr/cogitator/dreadnought/),
[sarcophagus-aws](/stc/fr/cogitator/sarcophagus-aws/),
[sarcophagus-kvm](/stc/fr/cogitator/sarcophagus-kvm/) et
[vm](/stc/fr/cogitator/vm/), qui garde une fenêtre de GC de 5 jours.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.nixHousekeeping.enable` | bool | `false` | Active la relique |
| `stc.relics.nixHousekeeping.gc.enable` | bool | `true` | GC planifié (`nix.gc.automatic`) |
| `stc.relics.nixHousekeeping.gc.dates` | string | `"weekly"` | Quand le GC tourne (expression calendaire systemd) |
| `stc.relics.nixHousekeeping.gc.keepDays` | entier positif ou nul | `30` | Supprime les générations et chemins du store plus anciens |
| `stc.relics.nixHousekeeping.minFreeGiB` | null ou entier positif | `5` | `nix.settings.min-free` ; `null` coupe la collecte pendant les builds |
| `stc.relics.nixHousekeeping.maxFreeGiB` | entier positif | `15` | `nix.settings.max-free` ; doit dépasser `minFreeGiB` |
| `stc.relics.nixHousekeeping.optimise` | bool | `true` | Déduplication hebdomadaire du store (sautée dans un conteneur) |
| `stc.relics.nixHousekeeping.deprioritiseBuilds` | bool | `true` | Les builds et le GC cèdent la place aux services |
| `stc.relics.nixHousekeeping.journal.systemMaxUse` | null ou string | `"500M"` | `SystemMaxUse` de journald |
| `stc.relics.nixHousekeeping.journal.maxRetentionSec` | null ou string | `"1month"` | `MaxRetentionSec` de journald |

Tout ce que la relique écrit en dessous est en `mkDefault`. Si tu poses
toi-même `nix.gc.options` ou une clé journald, ta valeur gagne sans `mkForce`.

Sur un petit disque (un volume racine cloud par défaut, un petit qcow2), 5 et
15 Gio pèsent lourd, et presque chaque build déclencherait une collecte. Baisse
les deux valeurs.

Si tu nettoies déjà le store avec `nh clean` (`programs.nh.clean.enable`),
nixpkgs prévient que ça recoupe `nix.gc.automatic` : pose `gc.enable = false`.

## GC planifié et GC sous pression ne font pas la même chose

`nix.gc` gère la rétention : une fois par semaine, les vieilles générations
partent. Il ne fait rien pour un build qui remplit le disque un mardi.
`min-free` / `max-free` sont la soupape : quand l'espace libre passe sous
`minFreeGiB` **pendant** un build, Nix collecte jusqu'à libérer `maxFreeGiB`,
et le build continue. Cela évite qu'un `nixos-rebuild switch` à distance tombe
à court de place en plein milieu. Il faut les deux.

## Pourquoi un timer et pas `auto-optimise-store`

`nix.settings.auto-optimise-store` déduplique chaque chemin au moment où il est
construit, donc chaque switch en paie le prix. Le timer hebdomadaire obtient la
même déduplication hors du chemin critique, et l'amont le fait déjà tourner en
priorité CPU et IO `idle`.

## Comment les builds cèdent la place

Avec `deprioritiseBuilds` :

- Le démon Nix, et donc chaque build, tourne avec la politique CPU `batch` et la
  classe IO `best-effort` à sa priorité la plus basse (7).
- Le démon reçoit `OOMScoreAdjust=250` : quand la mémoire manque, le noyau tue
  un build avant un service.
- Le GC planifié tourne en CPU `batch` et IO `idle`.

La classe IO du démon n'est **pas** `idle`, contrairement à srvos. La
description de l'option amont prévient que `idle` peut affamer une mise à jour
de configuration sur une machine chargée, et sur un serveur, cette mise à jour
est justement le rebuild dont tu as besoin. Une machine dédiée aux builds veut
l'inverse : pose `deprioritiseBuilds = false`.

## Conteneurs, et hôtes sans Nix

Dans un conteneur NixOS, le store appartient à l'hôte : son GC, sa
déduplication et la pression sur son disque regardent l'hôte. Sous
`boot.isContainer`, la relique saute le GC, `min-free` / `max-free` et le timer
d'optimisation. nixpkgs y coupe aussi `nix.optimise.automatic`, et la relique ne
le contredit pas.

Avec `nix.enable = false` (une image appliance sans Nix), la relique ne touche à
aucun réglage Nix. Sinon, l'amont refuserait `nix.gc.automatic` sans Nix.

Le plafond du journal s'applique dans les deux cas.

## Volontairement absent

`nix.gc.randomizedDelaySec` et un mode GC `--max-freed` ont été écartés quand la
relique a été cadrée. Dans cette relique, `min-free` / `max-free` gèrent la
pression sur le disque.

## Épreuve

`provings/docker-server.nix` fait chaque vérification deux fois : sur un nœud
qui porte la relique, puis sur un nœud où elle est coupée. Il vérifie :

- `min-free` et `max-free` dans `/etc/nix/nix.conf` ;
- le timer `nix-gc` et sa fenêtre de 30 jours ;
- l'ordonnancement et l'`OOMScoreAdjust` que systemd a réellement appliqués à
  `nix-daemon` et `nix-gc` ;
- les plafonds de journald.

Chaque vérification doit réussir sur le premier nœud et échouer sur le second.
`provings/vm.nix` n'a pas changé et vérifie toujours la fenêtre de 5 jours de
vm, ce qui prouve que les options ont gardé leur comportement en changeant de
place.

## Voir aussi

- [Profil VM](/stc/fr/cogitator/vm/) : les options `stc.cogitator.vm.nix.gc.*` renommées
- [Survie des serveurs](/stc/fr/relics/server-survivability/)
