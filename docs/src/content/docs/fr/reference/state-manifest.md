---
title: Manifeste d'état
description: Où les reliques STC gardent leur état persistant, de quoi il s'agit, et comment lire la liste de ton hôte.
---

**Module :** `stc.nixosModules.relics-state` (chaque relique ci-dessous l'importe)

Certaines reliques créent un état persistant : certificats, bases de données,
clés. Chacune déclare ce qu'elle crée dans `stc.relics.state.paths`, ce qui
permet de voir la liste complète d'un hôte sans lire le source des reliques :

```bash
nix eval --json .#nixosConfigurations.<hôte>.config.stc.relics.state.paths | jq
```

```json
[
  {
    "path": "/srv/docker/crowdsec/data",
    "type": "directory",
    "description": "CrowdSec's local API database: decisions (active bans), alerts and machine registrations.",
    "kind": "data"
  }
]
```

Une entrée n'apparaît que si sa relique est activée. Son chemin vient des
options de la relique (`dataDir`, `services.openssh.hostKeys`, le
`StateDirectory` de Vaultwarden) : si tu as déplacé un chemin, il apparaît là
où tu l'as mis. `type` dit s'il s'agit d'un fichier (`file`) ou d'un
répertoire (`directory`).

:::caution[Descriptif seulement]
Rien dans STC ne lit cette liste. Elle ne sauvegarde rien, et elle ne rend rien
persistant sous [impermanence](/stc/fr/relics/impermanence/). Elle dit **ce qui
existe**. C'est à ta sauvegarde et à ton
`stc.relics.impermanence.extraDirectories` d'en tirer les conséquences.
:::

## Types

| `kind` | Sens | Sauvegarde |
|---|---|---|
| `data` | Perdu, c'est perdu | À sauvegarder |
| `credentials` | Clés et secrets | À sauvegarder, chiffrés à part des données ordinaires |
| `cache` | Se reconstruit tout seul | Inutile |
| `log` | De l'historique, pas de l'état | À garder aussi longtemps que tu en as besoin |

## Ce que déclare chaque relique

| Relique | Chemin | `type` | `kind` |
|---|---|---|---|
| `relics-docker-traefik` | `<dataDir>/acme.json` | file | credentials |
| `relics-docker-traefik` | `<dataDir>/logs` | directory | log |
| `relics-docker-traefik` | `<dataDir>/conf/traefik_dynamic.yml` (quand `dynamicConfigFile` n'est pas posé : tu l'écris à la main) | file | data |
| `relics-docker-crowdsec` | `<dataDir>/data` | directory | data |
| `relics-docker-crowdsec` | `<dataDir>/etc` | directory | credentials |
| `relics-traefik` | `services.traefik.dataDir` (`/var/lib/traefik`) | directory | credentials |
| `relics-vaultwarden` | `/var/lib/vaultwarden` (`/var/lib/bitwarden_rs` avec un `stateVersion` antérieur à 24.11) | directory | data |
| `relics-vaultwarden` | `/var/backup/vaultwarden` (avec `backup = true`) | directory | data |
| `relics-hardening-ssh` | chaque chemin de `services.openssh.hostKeys` | file | credentials |
| `relics-zfs` | `/var/log/zed.debug.log` | file | log |
| `relics-smart` | `/var/lib/smartmontools` | directory | cache |

Le répertoire de Vaultwarden est classé `data`, mais il contient aussi
`rsa_key.pem`, la clé qui signe les jetons de connexion. Si tu chiffres les
secrets à part, inclus-le.

Les autres reliques NixOS ne créent aucun état qui vaille d'être restauré. Les
reliques Home Manager sont hors périmètre : elles vivent dans un autre système
de modules. La seule à avoir un vrai état est le profil de zen-browser
(`~/.zen`).

La liste couvre l'état que créent les **reliques**. Le profil docker-server
active Docker lui-même, et `/var/lib/docker` contient tes propres images et
volumes. Il n'est donc pas déclaré ici : ce qu'il faut en garder dépend de tes
applications.

## Alimenter l'impermanence

Certaines entrées sont déjà persistantes quand l'impermanence est active, et
les lister une seconde fois empêche l'impermanence d'évaluer (elle refuse les
doublons) :

- les reliques Traefik et Vaultwarden natives rendent leurs répertoires
  persistants ;
- la relique d'impermanence rend persistants `/var/log` (donc le journal de ZED)
  et les clés hôte SSH par défaut.

Il reste surtout le `dataDir` des reliques Docker (`/srv/docker/…` par défaut).
Place-le sur un dataset persistant, ou liste les entrées toi-même, répertoires
et fichiers à part :

```bash
m=$(nix eval --json .#nixosConfigurations.<hôte>.config.stc.relics.state.paths)
echo "$m" | jq -r '.[] | select(.path | startswith("/srv/docker/")) | select(.type == "directory") | .path'  # extraDirectories
echo "$m" | jq -r '.[] | select(.path | startswith("/srv/docker/")) | select(.type == "file") | .path'       # extraFiles
```

## Épreuve

- `provings/docker-server.nix` vérifie que chaque chemin du manifeste existe sur
  l'hôte démarré, et qu'un nœud sans CrowdSec n'en liste aucun chemin. Le
  `traefik_dynamic.yml` écrit à la main doit être listé, mais rien ne le crée
  sur un nœud neuf.
- `provings/hardening.nix` vérifie que les clés hôte du manifeste sont
  exactement celles que charge `sshd -T`.
