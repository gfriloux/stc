---
title: Variante VM
description: Démarrer un host STC en VM QEMU locale, ses parties dépendantes de secrets, d'images et de pools neutralisées.
---

**Module :** `stc.nixosModules.relics-vm-variant`

NixOS sait démarrer n'importe quelle configuration en VM QEMU locale. Cette
relique fait que ça marche vraiment pour un host construit avec STC.

```bash
nix build .#nixosConfigurations.<host>.config.system.build.vm
./result/bin/run-<host>-vm
```

C'est la marche manquante entre *ça évalue* et *je l'ai déployé en prod* : un
vrai démarrage, du vrai systemd, de vraies unités, sans risque. Elle compte
surtout là où une erreur verrouille — un host joignable seulement par VPN, ou un
changement qui touche `sudo`, `users` ou `sshd`.

Trois choses empêchent un `system.build.vm` nu de monter sur un host STC, et les
trois viennent de reliques STC : tout consommateur les rencontre donc, et
écrirait le même contournement.

| Obstacle | Pourquoi ça échoue en VM |
|----------|--------------------------|
| Secrets | Un host qui dérive sa clé de `/etc/ssh/ssh_host_ed25519_key` n'a aucune clé dans une VM neuve : l'activation des secrets échoue, et tout ce qui dépend d'un chemin de secret tombe avec elle. |
| Conteneurs | Les unités `oci-containers` tentent de télécharger leurs images. Une VM sans identifiants de registre, et souvent sans réseau sortant, ne peut pas. |
| ZFS / impermanence | La relique impermanence fait un rollback de dataset depuis un service initrd, et la relique ZFS force l'import du pool racine. Dans une VM il n'y a ni le pool, ni l'instantané. |

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.vmVariant.enable` | bool | `false` | Active le câblage de variante VM |
| `stc.relics.vmVariant.disableZfs` | bool | `true` | Éteint `stc.relics.zfs` dans la VM |
| `stc.relics.vmVariant.disableImpermanence` | bool | `true` | Éteint `stc.relics.impermanence` dans la VM |
| `stc.relics.vmVariant.disableContainers` | bool | `true` | Vide `virtualisation.oci-containers.containers` dans la VM |
| `stc.relics.vmVariant.rootPassword` | chaîne ou null | `null` | Mot de passe root en clair, VM uniquement |
| `stc.relics.vmVariant.skipActivationScripts` | liste de chaînes | `[]` | Scripts d'activation dont le corps est vidé dans la VM |
| `stc.relics.vmVariant.maskUnits` | liste de chaînes | `[]` | Services systemd désactivés dans la VM |

## Elle ne peut pas affaiblir un host réel

Tout ce que cette relique écrit va dans `virtualisation.vmVariant`, et nulle part
ailleurs. En amont, cette variante est construite par `extendModules` : c'est donc
une seconde évaluation, séparée, dont le seul consommateur est
`system.build.vm`.

Ce n'est pas une promesse, c'est une vérification. La dérivation de production est
bit pour bit identique, relique activée :

```bash
nix eval .#nixosConfigurations.<host> --apply 'base: let
  on = base.extendModules {
    modules = [{ stc.relics.vmVariant.enable = true; }];
  };
in base.config.system.build.toplevel.drvPath
   == on.config.system.build.toplevel.drvPath'
# => true
```

Lancez-la sur votre propre host si vous préférez ne pas nous croire sur parole.
Une relique dont le métier est « désactiver des protections » invite exactement à
la mauvaise lecture : c'est pour cette propriété que le mécanisme a été choisi,
pas pour sa commodité.

## Ce que cette VM prouve — et ce qu'elle ne prouve pas

| Prouve | Ne prouve pas |
|--------|---------------|
| La machine démarre | Quoi que ce soit sur vos conteneurs |
| Les unités systemd démarrent, et dans le bon ordre | Quoi que ce soit sur vos secrets |
| Utilisateurs, groupes et shells sont ceux déclarés | Quoi que ce soit sur votre agencement de stockage |
| Réseau et DNS montent | Que le noyau de production fonctionne (voir `disableZfs` plus bas) |
| Les règles de pare-feu sont celles que vous croyez | Qu'un vrai pool s'importe, ni qu'un rollback se comporte bien |

Les trois choses qu'elle ne prouve pas sont exactement les trois qu'elle éteint.
Un garde-fou qui surévalue sa couverture est pire que pas de garde-fou : lisez un
démarrage vert comme « le câblage est sain », pas comme « c'est déployable ».

## Exemple d'utilisation

```nix
# flake.nix
modules = [
  stc.nixosModules.relics-vm-variant
  ./configuration.nix
];

# configuration.nix
{
  stc.relics.vmVariant = {
    enable = true;

    # Une porte d'entrée sans le matériel cryptographique du host — voir
    # l'avertissement ci-dessous.
    rootPassword = "vm";

    # Neutraliser le backend de secrets. STC ne sait pas lequel vous utilisez,
    # donc nommez son script d'activation vous-même :
    skipActivationScripts = ["setupSecrets"];               # sops-nix
    # skipActivationScripts = ["agenixInstall" "agenixNewGeneration"];  # agenix

    # Pour un backend qui installe ses secrets depuis une unité :
    # maskUnits = ["sops-install-secrets"];
  };
}
```

:::caution[Sans `rootPassword`, personne n'entre]
Neutraliser le backend de secrets neutralise aussi les clés autorisées qu'il
installe. Une VM sans mot de passe root est alors une VM dans laquelle vous ne
pouvez pas entrer : elle démarre, et vous la regardez de l'extérieur.

`rootPassword` n'est volontairement pas activé par défaut : un mot de passe qui
fuiterait vers un chemin non-VM serait un risque. Ce n'est pas non plus une
exception à la [règle des secrets en `*File`](/stc/fr/architecture/) — la valeur
ne quitte jamais la variante VM, donc elle n'atteint jamais un host réel. C'est un
paramètre de banc d'essai.
:::

## Pourquoi il n'y a pas de `disableSops`

STC est agnostique du backend de secrets : il n'y a ni module sops ni module
agenix dans ce dépôt, seulement la convention `*File`. Une relique qui écrirait
`sops.*` graverait un backend dans le marbre — et ce serait une erreur
d'évaluation dure pour qui ne l'importe pas, puisque la variante VM étend *votre*
liste de modules : l'option `sops` n'existe que si vous l'avez apportée.

D'où la paire générique. `skipActivationScripts` **vide** le corps d'un script
plutôt que de retirer l'attribut, pour que les autres scripts déclarant
`deps = [ "setupSecrets" ]` continuent de résoudre.

:::note[`maskUnits` échoue en silence]
Un nom d'unité qui ne correspond à rien est accepté sans bruit : il produit une
unité désactivée et aucune erreur, donc une faute de frappe passe inaperçue. Il
n'existe aucun moyen de vérifier l'existence d'une unité à l'évaluation sans
casser le cas légitime.
:::

## Les bascules sont la sortie de secours

La relique écrit avec `lib.mkForce`. Si vous surchargez déjà l'un de ces réglages
dans votre propre `virtualisation.vmVariant`, vous obtenez un conflit de
priorité — et la sortie est la bascule correspondante, pas un second `mkForce` :

```nix
stc.relics.vmVariant = {
  enable = true;
  disableZfs = false;   # garder la relique ZFS vivante dans la VM
};
```

C'est tout l'intérêt de cette granularité : on peut vouloir ses conteneurs
éteints mais son ZFS debout.

:::note[`disableZfs` change le noyau]
La relique ZFS épingle un noyau LTS compatible ZFS. L'éteindre dans la VM
signifie que la VM tourne sur un noyau générique, et non sur celui de la
production. Assumé : la cible de ce garde-fou est le câblage systemd, pas le
pilote de stockage. Posez `disableZfs = false` pour garder le noyau de
production, au prix d'un import de pool qui échouera.
:::

## À ne pas confondre avec `provings/`

Les [épreuves](/stc/fr/provings/) de STC sont de la QA interne : chacune démarre
une VM avec un *cogitator* activé et vérifie qu'il tient sa promesse. Elles
testent les modules de STC. Cette relique va dans l'autre sens — c'est ce qui vous
permet de démarrer **votre** configuration de host.

Aucun cogitator n'active cette relique. Décider qu'un mot de passe root atterrit
dans vos builds de VM n'est pas à la main d'un profil.

## Voir aussi

- [Vue d'ensemble des reliques](/stc/fr/relics/) — toutes les reliques
- [Impermanence](/stc/fr/relics/impermanence/) — le rollback que cette relique désactive en VM
- [ZFS](/stc/fr/relics/zfs/) — l'import de pool que cette relique désactive en VM
