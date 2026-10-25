---
title: Délégation d'unités par polkit
description: Permettre à un groupe de démarrer, arrêter ou redémarrer des unités systemd nommées, sans sudo.
---

**Module :** `stc.nixosModules.relics-polkit-units`

`sudo systemctl restart docker-immich-server` fonctionne, mais
`sudo systemctl` donne la main sur **toutes** les unités de l'hôte. Le besoin
est souvent plus étroit : redémarrer un conteneur, ou démarrer un service à la
demande déclaré avec `wantedBy = lib.mkForce []`. La relique génère la règle
polkit qui accorde exactement cela :

```nix
stc.relics.polkitUnits = {
  enable = true;
  delegations = [
    {
      group = "ops";
      units = ["docker-immich-server" "docker-immich-redis"];
    }
  ];
};
```

Un membre de `ops` lance alors `systemctl restart docker-immich-server`, sans
sudo ni mot de passe.

Aucun cogitator ne l'active.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.polkitUnits.enable` | bool | `false` | Active la relique (et active polkit) |
| `stc.relics.polkitUnits.delegations` | liste | `[]` | Qui peut faire quoi sur quelles unités. Vide, rien n'est accordé |
| `delegations.*.group` | string | — | Groupe dont les membres reçoivent la délégation. Doit exister dans `users.groups` |
| `delegations.*.units` | liste de chaînes | `[]` | Noms exacts d'unités, en identifiants systemd. `.service` est ajouté à un nom sans suffixe de type. Chacune doit être installée par cette configuration |
| `delegations.*.unitPrefixes` | liste de chaînes non vides | `[]` | Préfixes, résolus au build en la liste des unités installées qu'ils couvrent |
| `delegations.*.actions` | liste de verbes | `["start" "stop" "restart"]` | Verbes accordés : `start`, `stop`, `restart`, `try-restart`, `reload`, `reload-or-restart`, `reload-or-try-restart` |

Le build échoue quand une délégation :

- ne nomme ni unité ni préfixe ;
- nomme une unité que cette configuration n'installe pas ;
- a un préfixe qui ne correspond à aucune unité installée.

## Chaque nom accordé doit exister

`systemd-run` demande à polkit la même permission que `systemctl start`, avec
le nom d'unité **choisi par l'appelant**. systemd refuse de créer une unité
transitoire sous un nom qui a déjà un fichier d'unité, et accepte tout autre
nom. Une règle qui accepterait un nom sans fichier d'unité laisserait donc un
membre lancer `systemd-run --unit=<ce nom> <n'importe quelle commande>`
**en root**. Un tel nom peut être :

- une unité ajoutée plus tard sous un préfixe ;
- une faute de frappe ;
- une unité désactivée.

C'est pourquoi la relique résout chaque nom au build :

- un nom exact doit être une unité installée par cette configuration
  (`systemd.services`, l'unité d'un conteneur, …), ou une instance d'un modèle
  installé (`foo@bar` quand `foo@` est déclaré) ;
- un préfixe devient la liste des unités installées qu'il couvre ;
- la règle compare à cette liste fermée et ne teste aucun motif à
  l'exécution.

Une unité livrée seulement par un paquet (`systemd.packages`) n'est pas dans
cette liste. Pour la déléguer, déclare-la avec un
`systemd.services.<nom> = {};` vide.

## Ce que signifie désormais l'appartenance au groupe

:::caution[Cela élargit des privilèges]
Un membre d'un groupe délégué peut arrêter les unités listées, et donc ce
qu'elles servent. Redémarrer une unité relance aussi ses
`ExecStartPre`/`ExecStart` sous l'utilisateur de l'unité, souvent root. Il ne
peut pas changer ce qu'exécute une unité listée : son fichier d'unité est dans
le store Nix. Ajoute des gens à ce groupe comme tu les ajouterais à `wheel`
pour ces unités-là.
:::

Tout démarrage ou arrêt entraîne deux effets que polkit ne peut pas
restreindre :

- **Les dépendances suivent.** Arrêter une unité arrête aussi ce qui en dépend
  par `Requires=` ou `BindsTo=`. En démarrer une démarre aussi ce qu'elle
  `Requires=` ou `Wants=`.
- **L'appelant choisit le mode de job.** `systemctl start --job-mode=flush`
  annule tous les jobs en attente sur l'hôte, pas seulement ceux de l'unité.
  `isolate` ne s'applique qu'à une cible `AllowIsolate=yes` que tu as
  déléguée.

Chaque autorisation est bornée de trois façons, et tout ce qui sort de ce
cadre est refusé :

- **Groupe.** Les utilisateurs hors du groupe sont refusés.
- **Unité.** Une unité absente de la liste résolue est refusée.
- **Verbe.** Seules les `actions` listées passent.
  - `kill`, `set-property`, `clean` et `bind-mount` ne sont jamais accordés :
    ils changent ce que fait une unité ou effacent son état.
  - Geler et dégeler demandent `stop` et `start` à polkit, mais la politique
    D-Bus de systemd les refuse elle-même aux appelants sans privilèges.

## `units` ou `unitPrefixes`

| | `units` | `unitPrefixes` |
|---|---|---|
| Couvre | Exactement les noms listés | Toute unité installée dont l'identifiant commence par le préfixe, recalculé à chaque rebuild |
| Risque | Rien au-delà de la liste | Accorde trop par construction : une unité ajoutée plus tard avec le préfixe est incluse au rebuild suivant, quel que soit son type (`.timer`, `.socket`, …) |
| Entretien | Une unité nouvelle ou renommée demande une nouvelle entrée | Aucun |

Les instances de modèles (`foo@bar.service`) ne sont pas des unités
installées : un préfixe ne les couvre pas. Liste chaque instance par son nom.

Liste les identifiants canoniques, pas les alias : systemd transmet toujours
l'identifiant canonique à polkit, donc un alias dans la liste ne correspond
jamais.

## Pourquoi enable et disable ne sont jamais délégués

systemd interroge polkit pour enable, disable, mask, link et preset sous une
autre action, `org.freedesktop.systemd1.manage-unit-files`, et ne transmet
**aucun nom d'unité** avec elle. Une règle ne peut pas la limiter à certaines
unités. L'accorder permet au groupe de lier un fichier d'unité qu'il a écrit,
puis de le démarrer en root. La relique ne l'accorde jamais.

Pour un service à la demande, tu n'en as pas besoin : déclare l'unité sans
`wantedBy` (`wantedBy = lib.mkForce []`) et délègue `start` et `stop`.

## Comment la règle est construite

La relique génère une seule règle à partir de `delegations` et l'écrit dans
`security.polkit.extraConfig` :

- Elle n'agit que sur `org.freedesktop.systemd1.manage-units`.
- Elle vérifie que polkit a bien transmis une unité et un verbe avant de s'en
  servir.
  - Les appels au niveau du gestionnaire (`systemctl reset-failed` sans unité,
    l'annulation d'un job) ne transmettent ni l'un ni l'autre.
  - Sans cette vérification, la règle lève une exception, et polkit journalise
    `TypeError: cannot read property 'indexOf' of undefined`.
- Elle renvoie `YES` ou rien ; elle ne refuse jamais. Un `YES` termine
  l'évaluation de polkit, donc il l'emporte sur une règle que polkit lit
  après elle.

## Avec les reliques de durcissement

La [relique de durcissement du système de fichiers](/stc/fr/relics/hardening/)
monte `/proc` avec `hidepid=2`, ce qui casse certains outils qui lisent les
processus des autres utilisateurs. La délégation n'en fait pas partie : polkit
identifie l'appelant par D-Bus. La relique n'assouplit donc aucun réglage de
durcissement.

## Épreuve

`provings/polkit-units.nix` démarre une VM avec une délégation et lance
`systemctl` sous deux utilisateurs sans privilèges. La délégation couvre une
unité par son nom, une instance de modèle et un préfixe.

Accordé à un membre :

- redémarrer, arrêter et démarrer l'unité nommée ;
- redémarrer une unité couverte seulement par le préfixe ;
- démarrer et arrêter l'instance listée.

Refusé :

- une autre instance ;
- une autre unité ;
- un autre verbe (`reload-or-restart`, `kill`) ;
- geler et dégeler, par `systemctl` comme par D-Bus ;
- `enable` ;
- un utilisateur hors du groupe ;
- un appel du gestionnaire sans unité ;
- `systemd-run --unit=` sous un nom que le préfixe aurait couvert, et sous
  les noms délégués eux-mêmes.

Avant que les noms soient résolus au build, l'épreuve a mesuré que
`systemd-run` sous le nom couvert par le préfixe tournait en root.

polkit ne journalise aucune erreur de règle. Un contrôle positif vérifie que
c'est bien son journal qui est lu.

Chaque vérification est rejouée après un remontage de `/proc` avec
`hidepid=2,gid=proc`.
