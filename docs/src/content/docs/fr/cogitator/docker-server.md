---
title: Profil serveur Docker
description: cogitator-docker-server — pile Docker reverse proxy complète en une seule option.
---

**Module :** `stc.nixosModules.cogitator-docker-server`

Pile Docker reverse-proxy complète : Traefik + un socket-proxy filtrant + CrowdSec IDS/IPS,
avec notifications d'échec optionnelles. Activer ceci est équivalent à activer
`stc.relics.docker.traefik`, `stc.relics.docker.socketProxy`, et
`stc.relics.docker.crowdsec` individuellement, plus la configuration du démon Docker.

Utilise les reliques individuelles directement si tu as besoin d'un contrôle plus fin —
par exemple, si tu veux Traefik sans CrowdSec, ou un provider de notification différent.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.docker-server.enable` | bool | `false` | Active la pile serveur Docker STC |
| `stc.cogitator.docker-server.notify.enable` | bool | `false` | Active les notifications d'échec pour la pile (nécessite `notifyCommand`) |

## Ce qu'il active

Lorsqu'il est activé, ce profil pose :

```nix
stc.relics.docker.traefik.enable = true;
stc.relics.docker.socketProxy.enable = true;  # Traefik utilise le proxy, pas le socket brut
stc.relics.docker.crowdsec.enable = true;
stc.relics.docker.notify.enable = cfg.notify.enable;  # off sauf opt-in explicite

virtualisation.docker.enable = true;
virtualisation.docker.autoPrune.enable = lib.mkDefault false;  # voir plus bas
virtualisation.oci-containers.backend = "docker";
```

### Pourquoi `autoPrune` est désactivé

`virtualisation.docker.autoPrune` peut coucher toute la pile au boot, donc ce
profil le laisse éteint.

En amont, `autoPrune.persistent` vaut `true` par défaut et `randomizedDelaySec`
`"0"`. Un timer dont la fenêtre hebdomadaire a été manquée — un redémarrage
imprévu, ou une machine restée éteinte un moment — tire donc **immédiatement** au
boot suivant, dès que `docker.service` est up, pendant que les conteneurs
démarrent encore. À cet instant, les réseaux créés par ce profil n'ont rien
d'attaché : `docker system prune -f` les supprime comme inutilisés. Chaque
conteneur qui en référence un échoue alors sur `network not found`, atteint
`StartLimitBurst`, et reste par terre.

La récupération n'est pas automatique : les unités réseau sont des oneshots
`RemainAfterExit` sans `ExecStop` (délibérément — voir
[les reliques docker](/stc/fr/relics/docker/)), donc rien ne recrée un réseau
supprimé derrière leur dos. Le même danger existe, plus rarement, pour un
conteneur arrêté ou en crashloop au moment du prune hebdomadaire — c'est pourquoi
`persistent = false` seul ne suffit pas.

Les images inutilisées font grossir le disque progressivement et visiblement ;
perdre le réseau de tous les conteneurs est une panne. L'option reste la tienne :

```nix
# Nettoyage hebdomadaire, sans le rattrapage au boot qui crée la course.
virtualisation.docker.autoPrune = {
  enable = true;
  persistent = false;
  randomizedDelaySec = "45min";
};
```

:::caution
Même sous cette forme, un conteneur arrêté au moment du prune peut perdre son
réseau définitivement. Si tu l'active, assure-toi de savoir relancer les unités
`docker-network-*.service`.
:::

## Options requises

Le profil active les conteneurs mais ne fournit pas les valeurs spécifiques à la machine.
Tu dois les poser toi-même :

| Option | Pourquoi |
|--------|----------|
| `stc.relics.docker.traefik.image` | Requise — STC ne fournit aucun défaut (épingle-la, `# renovate`) |
| `stc.relics.docker.socketProxy.image` | Requise — STC ne fournit aucun défaut (épingle-la, `# renovate`) |
| `stc.relics.docker.crowdsec.image` | Requise — STC ne fournit aucun défaut (épingle-la, `# renovate`) |
| `stc.relics.docker.traefik.acme.email` | Enregistrement Let's Encrypt |
| `stc.relics.docker.crowdsec.dataDir` | Où CrowdSec stocke ses données |
| `stc.relics.docker.notify.notifyCommand` | Uniquement si `notify.enable = true` — le transport d'alerte |

## Exemple d'utilisation minimal

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-docker-server
  ./configuration.nix
];

# configuration.nix
{ config, pkgs, ... }:
{
  stc.cogitator.docker-server.enable = true;

  # Requis : images (STC ne fournit aucun défaut — épingle-les, renovate scanne ton dépôt)
  stc.relics.docker.traefik.image = "traefik:v3.7.6"; # renovate
  stc.relics.docker.socketProxy.image = "tecnativa/docker-socket-proxy:0.3.0"; # renovate
  stc.relics.docker.crowdsec.image = "crowdsecurity/crowdsec:v1.7.8"; # renovate

  # Requis : valeurs spécifiques à la machine
  stc.relics.docker.traefik.acme.email = "ops@example.com";
  stc.relics.docker.crowdsec.dataDir = "/srv/docker/crowdsec";

  # Optionnel : notifications d'échec (off par défaut). Une fois activées, fournis
  # le transport — il reçoit STC_NOTIFY_SERVICE / STC_NOTIFY_HOSTNAME.
  # stc.cogitator.docker-server.notify.enable = true;
  # stc.relics.docker.notify.notifyCommand = ''
  #   ${pkgs.curl}/bin/curl -s \
  #     -d "$STC_NOTIFY_SERVICE failed on $STC_NOTIFY_HOSTNAME" \
  #     "https://ntfy.sh/$(cat ${config.sops.secrets."ntfy/topic".path})"
  # '';

  # Optionnel : ouvrir les ports pour Traefik (la relique traefik le fait aussi automatiquement)
  # stc.relics.hardening.network.allowedTCPPorts = [ 22 80 443 ];
}
```

:::note[Secrets]
`notifyCommand` et `traefik.dynamicConfigFile` acceptent n'importe quel chemin de fichier.
Utilise sops-nix, agenix, ou tout autre gestionnaire de secrets — STC se fiche de
savoir comment le fichier y arrive.
:::

## Voir aussi

- [Reliques Docker](/stc/fr/relics/docker/) — Traefik, socket-proxy, CrowdSec et notify en détail
- [Schématic : aws-ami](/stc/fr/schematics/aws-ami/) — un exemple de production complet utilisant ce profil
