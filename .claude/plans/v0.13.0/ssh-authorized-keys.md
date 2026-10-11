# Plan v0.13.0 — Chemins critiques, chantier B : les clés SSH viennent du flake

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Refactoring Internal Code*
> (option nouvelle sur une relique existante, pas de nouvelle relique).
> Chantier A d'abord : [`plan.md`](plan.md).
>
> **Branche :** `feat/ssh-system-authorized-keys` — **Issue :** [#71](https://github.com/gfriloux/stc/issues/71)

---

## Type

Option nouvelle + défaut durci sur `relics/nixos/hardening/ssh.nix`. Classé
**architectural** parce qu'il touche le chemin d'authentification : l'erreur se
paie en lockout d'un hôte distant, pas en build rouge.

## Objectif

Retirer le répertoire personnel du chemin d'authentification SSH : `sshd` ne lit
plus que `/etc/ssh/authorized_keys.d/%u`, c'est-à-dire ce que le flake déclare.
Avec un garde-fou à l'évaluation pour les services qui gèrent leurs propres clés.

## Pourquoi

Mesuré sur l'arbre actuel :

```
$ nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.services.openssh.authorizedKeysFiles
[ "%h/.ssh/authorized_keys" "/etc/ssh/authorized_keys.d/%u" ]
```

Le répertoire personnel **est** dans le chemin d'auth. Tout ce qui sait écrire
dans `~/.ssh` d'un utilisateur — un service compromis tournant sous son compte,
un bind-mount de conteneur mal cadré, un outil de synchronisation — accorde un
accès SSH persistant, invisible à la configuration Nix.
`users.users.<n>.openssh.authorizedKeys.keys` cesse d'être toute la vérité.

Ça se marie exactement avec `users.mutableUsers = false`, que les profils
serveur de STC posent déjà : on a déjà décidé que les comptes viennent du flake
(c'est l'argument porteur du non-goal `pam_pwquality`, cf. `SECURITY_POLICY.md`).
Les clés, non. L'incohérence est là.

## Prémisses vérifiées (nixpkgs `4975466`)

| Fait | Où | Conséquence |
|------|----|-------------|
| `services.openssh.authorizedKeysInHomedir` existe, type `bool`, défaut `true` | `nixos/modules/services/networking/ssh/sshd.nix:444-453` | **Le `lib.mkForce` proposé par l'issue est inutile.** Il y a un bouton amont pour exactement ça. |
| `authorizedKeysFiles = optional cfg.authorizedKeysInHomedir "%h/.ssh/authorized_keys" ++ [ "/etc/ssh/authorized_keys.d/%u" ]` | idem `:885-887` | Mesuré : avec `authorizedKeysInHomedir = false` → `[ "/etc/ssh/authorized_keys.d/%u" ]`, la valeur cible de srvos, **sans `mkForce`**. |
| `authorizedKeysFiles` est un `listOf str`, donc les définitions **fusionnent** (concaténation), elles ne remplacent pas | idem `:428` | Conséquence importante pour la doc : le verrou n'interdit pas d'ajouter un fichier, il retire seulement le défaut `~/.ssh`. Un consommateur qui a besoin d'un chemin précis l'ajoute sans toucher à l'option. |
| `settings.UseDns` a pour défaut `false` **en amont** | idem `:529-540` | Rien à écrire. L'issue le compte comme un acquis à prendre ; il est déjà pris. |
| `X11Forwarding = false` est déjà posé par la relique | `relics/nixos/hardening/ssh.nix:110` | Idem : zéro ligne de code, une ligne de doc. |
| Le module NixOS écrit les clés déclarées dans `etc/ssh/authorized_keys.d/<user>` | idem `:149` | La cible du verrou est bien le fichier que NixOS génère, donc un hôte 100 % déclaratif ne change pas de comportement. |
| Mesuré : `services.{gitea,forgejo,gitlab,gitolite,gerrit}` existent **tous** dans une éval NixOS nue | `nix eval …#nixosConfigurations.local-vm.options --apply` → `{ forgejo = true; gerrit = true; gitea = true; gitlab = true; gitolite = true; }` | On peut lire `config.services.<forge>.enable` dans une assertion sans risque d'option inconnue — contrairement au cas sops-nix de v0.12.0 (cf. `feedback-nix-patterns`). |
| `nixos/tests/ssh-keys.nix` fournit `snakeOilEd25519PrivateKey` / `…PublicKey` | nixpkgs | Le proving peut prouver une authentification réelle, pas seulement un rendu de configuration. |

## Décisions

### 1. `systemAuthorizedKeysOnly`, défaut `true`

Nom repris de l'issue. Implémenté par `services.openssh.authorizedKeysInHomedir
= false`, pas par un `mkForce` sur `authorizedKeysFiles` : on utilise le bouton
amont, et on laisse la liste ouverte aux ajouts d'un consommateur.

Défaut `true` parce que la relique est `hardening/` — c'est son métier d'être
stricte, et un défaut `false` ferait de l'option une documentation déguisée.

### 2. Garde-fou : assertion, pas exclusion automatique

srvos désactive le verrou *silencieusement* quand une forge Git est activée. STC
prend l'autre route et le dit : **assertion à l'évaluation**, message qui nomme
le remède.

L'argument est celui de `feedback-eval-guard-method` : mesurer le consommateur
avant de choisir. Ici, le consommateur qui active `services.gitea` sur un hôte
STC durci perd l'accès SSH de sa forge **au runtime**, à distance, sans rien de
rouge nulle part. Une assertion lui coûte une ligne dans sa configuration et est
impossible à rater ; une exclusion automatique affaiblit le durcissement sans
que personne ne l'ait décidé. Le build rouge est strictement moins cher que le
lockout silencieux.

La relique a déjà une assertion de la même famille (OpenSSH ≥ 9.9 pour
`mlkem768x25519-sha256`, `ssh.nix:66-72`) : la forme est maison, pas inventée.

Services couverts, tous mesurés présents : `gitea`, `forgejo`, `gitlab`,
`gitolite`, `gerrit`. Le message doit être lisible seul :

```
stc.relics.hardening.ssh: systemAuthorizedKeysOnly = true removes
~/.ssh/authorized_keys from sshd's search path, and services.gitea manages its
own authorized_keys file — it would lose all SSH access. Set
stc.relics.hardening.ssh.systemAuthorizedKeysOnly = false on this host, or add
the path the service needs to services.openssh.authorizedKeysFiles (it is a
list: definitions merge).
```

### 3. `UseDns` et `X11Forwarding` : aucun code

Mesuré : le premier est déjà `false` en amont, le second est déjà posé par la
relique. Même arbitrage que `pid_max` dans #43 (cf. `project-cis-issue-backlog`) :
on écrit la ligne ✅ dans la doc, on n'écrit pas de code qui redit un acquis.

### 4. `StreamLocalBindUnlink` : lié à la condition qui le rend utile

Il ne sert qu'à délier une socket Unix oubliée par un forwarding précédent. La
relique coupe déjà `AllowAgentForwarding`, `PermitTunnel`, `GatewayPorts`, et
`AllowTcpForwarding = cfg.allowedTCPForwarding` (défaut `false`) — sans
forwarding, il n'y a rien à délier, et le poser inconditionnellement serait du
décor.

Décision : `StreamLocalBindUnlink = cfg.allowedTCPForwarding`. Une ligne, vraie
exactement quand le réglage a un objet. Le commentaire du module dit pourquoi,
sinon quelqu'un « simplifiera » en `true`.

## Architecture

Aucune frontière déplacée : une option de plus sous
`stc.relics.hardening.ssh.*`, consommée uniquement par cette relique. Pas de
touche aux cogitators : le défaut `true` les traverse, et aucun n'active de
forge.

## Global Constraints

- Namespace canonique : `stc.relics.hardening.ssh.systemAuthorizedKeysOnly`.
- Pas d'alias `mkRenamedOptionModule` : option neuve, rien à renommer.
- Les trois schematics doivent continuer à évaluer.
- Le proving `hardening` couvre déjà sshd : il **doit** être étendu, pas doublé.
- Aucun secret : une clé publique n'est pas un secret, pas de suffixe `*File`.

## Review Focus

- **Le consommateur qui ne change rien** : si un de ses utilisateurs a une clé
  dans `~/.ssh/authorized_keys` qui n'est *pas* déclarée dans le flake, il perd
  l'accès au prochain switch. C'est le risque principal, il doit être en tête de
  la doc et de la note de release, avec la vérification préalable à lancer
  *avant* de switcher : `ls -l ~*/.ssh/authorized_keys` sur l'hôte, ou
  `getent passwd | …`. À écrire comme procédure, pas comme avertissement vague.
- L'assertion ne couvre que cinq services nommés. Tout autre logiciel gérant ses
  propres clés (compte SFTP-only, cible de sauvegarde qui laisse le pair
  ajouter une clé, `authorizedKeysCommand` maison) passe à travers. La doc doit
  décrire la **classe**, pas seulement la liste — sinon la liste se lit comme
  exhaustive.
- `services.openssh.authorizedKeysCommand` : un consommateur qui s'en sert n'est
  pas affecté (chemin distinct de `AuthorizedKeysFile`), à vérifier et à dire,
  parce que c'est la première question qu'on se posera.
- Le `vmVariant` est le banc d'essai de ce chantier (il ne désactive pas sshd) —
  contrairement au chantier A, où `disableZfs = true` le rend inopérant.

## Affected Files

- [ ] `relics/nixos/hardening/ssh.nix` — option, défaut, assertion, `StreamLocalBindUnlink`
- [ ] `provings/hardening.nix` — rendu `AuthorizedKeysFile` + authentification réelle
- [ ] `docs/src/content/docs/en/relics/hardening.md` — table d'options + section SSH
- [ ] `docs/src/content/docs/fr/relics/hardening.md` — idem
- [ ] `docs/src/content/docs/{en,fr}/reference/anssi-bp-028.md` — le guide (Open)SSH, pas BP-028
- [ ] `.claude/plans/v0.13.0/ssh-authorized-keys-progress.md` — ledger

## Atomic Steps

### Step 1 — L'option et le verrou

**Description :** `systemAuthorizedKeysOnly` (`bool`, défaut `true`) →
`services.openssh.authorizedKeysInHomedir = !cfg.systemAuthorizedKeysOnly`.
Description de l'option explicite sur le risque de lockout.

**Files changed :** `relics/nixos/hardening/ssh.nix`

**Interfaces :**
- Produit : `stc.relics.hardening.ssh.systemAuthorizedKeysOnly` (`bool`, défaut `true`).
- Produit : `services.openssh.authorizedKeysFiles == [ "/etc/ssh/authorized_keys.d/%u" ]` par défaut.

**Verification command(s) :**
```bash
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.services.openssh.authorizedKeysFiles --no-write-lock-file
# attendu : [ "/etc/ssh/authorized_keys.d/%u" ]
# mesuré avant changement : [ "%h/.ssh/authorized_keys" "/etc/ssh/authorized_keys.d/%u" ]
```

**Commit message :** `feat(hardening/ssh): read authorized keys only from the system path`

---

### Step 2 — L'assertion des forges

**Description :** une assertion dans le bloc `assertions` existant, déclenchée
quand `cfg.systemAuthorizedKeysOnly` et qu'un des cinq services est activé.
Message de la décision 2.

**Files changed :** `relics/nixos/hardening/ssh.nix`

**Interfaces :**
- Consomme : `cfg.systemAuthorizedKeysOnly` (Step 1).
- Lit : `config.services.{gitea,forgejo,gitlab,gitolite,gerrit}.enable` (présence mesurée).

**Verification command(s) :**
```bash
# cas positif : l'éval nominale passe toujours
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.toplevel.drvPath --no-write-lock-file

# cas négatif : forge activée => build rouge, message lisible
# sonde hors dépôt (scratchpad), même forme que les sondes de ce plan :
#   nixosSystem { modules = [ relics-hardening-ssh { services.gitea.enable = true; } ]; }
nix eval --impure --file <sonde>.nix
# attendu : échec d'assertion nommant systemAuthorizedKeysOnly
```

**Commit message :** `feat(hardening/ssh): fail the build when a Git forge would lose its keys`

---

### Step 3 — `StreamLocalBindUnlink`

**Description :** `StreamLocalBindUnlink = cfg.allowedTCPForwarding` + le
commentaire de la décision 4.

**Files changed :** `relics/nixos/hardening/ssh.nix`

**Verification command(s) :**
```bash
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.services.openssh.settings.StreamLocalBindUnlink --no-write-lock-file
```

**Commit message :** `feat(hardening/ssh): unlink stale forwarded sockets when forwarding is allowed`

---

### Step 4 — Le proving

**Description :** étendre le subtest `ssh hardening` de `provings/hardening.nix` :

1. `sshd -T` rend `authorizedkeysfile /etc/ssh/authorized_keys.d/%u` et **ne
   contient pas** `%h/.ssh`.
2. Une clé déclarée authentifie vraiment : `snakeOilEd25519PublicKey` dans
   `users.users.<n>.openssh.authorizedKeys.keys`, la privée copiée dans le
   nœud, `ssh -i … localhost true` réussit.
3. Une clé posée **à la main** dans `~/.ssh/authorized_keys` ne passe pas —
   c'est l'assert qui prouve le verrou, les deux premiers ne prouvent que le
   rendu. Sans lui, le proving est décoratif.

**Files changed :** `provings/hardening.nix`

**Verification command(s) :**
```bash
just test
nix build .#legacyPackages.x86_64-linux.provings.hardening -L --no-write-lock-file
```

**Commit message :** `test(provings): prove the system-only authorized keys path`

---

### Step 5 — Doc EN + FR

**Description :** table d'options + section SSH : ce que le verrou retire, la
**classe** de logiciels incompatible (forges Git, comptes SFTP-only, cibles de
sauvegarde qui laissent le pair ajouter une clé) et pas seulement les cinq
services asserts, la procédure de vérification avant switch, le fait que
`authorizedKeysFiles` fusionne (donc on ajoute sans désactiver), et les deux
lignes ✅ de la décision 3 (`UseDns`, `X11Forwarding` déjà acquis). Ligne dans la
matrice de référence côté **guide (Open)SSH**, jamais sous un `Rxx` de BP-028
(SSH est hors BP-028, décision de v0.4.0).

**Files changed :** `docs/src/content/docs/{en,fr}/relics/hardening.md`, `docs/src/content/docs/{en,fr}/reference/anssi-bp-028.md`

**Verification command(s) :**
```bash
just docs-parity
grep -rn "systemAuthorizedKeysOnly" docs/src/content/docs/en docs/src/content/docs/fr
```

**Commit message :** `docs(hardening): document the system-only authorized keys lockdown`

## Quality Gates

- [ ] `just ci`
- [ ] `just test` (proving `hardening` vert, avec les trois nouveaux asserts)
- [ ] Les trois schematics évaluent (`qcow2`, `awsImage`, `toplevel`)
- [ ] Boot `vmVariant` d'un hôte avec la relique : connexion SSH par clé déclarée
      réussie *dans la VM* avant toute recommandation de déploiement
- [ ] Cas négatif de l'assertion reproduit et son message relu
- [ ] Ledger à jour : arbitrage assertion vs exclusion, et le résultat des sondes
