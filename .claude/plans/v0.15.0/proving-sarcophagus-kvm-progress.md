# Ledger — plan: .claude/plans/v0.15.0/proving-sarcophagus-kvm.md

Pre-flight (2026-10-17, avant toute branche) : spike monté hors arbre et **vert**.
Le patron « image externe » de `nixos/tests/qemu-vm-external-disk-image.nix`
démarre le qcow2 de `cogitator-sarcophagus-kvm` sous `runNixOSTest`. Trois causes
racines traversées, chacune lue dans la source amont avant correctif :
  1. `nixos-install` échoue faute de `switch-to-configuration` —
     `nixos-test-base.nix:34` pose `system.switch.enable = mkDefault false`.
     Correctif : `system.switch.enable = true` sur le nœud (ce que fait le test amont).
  2. GRUB s'installe sur `/dev/disk/by-id/virtio-root` — `qemu-vm.nix:1183` pose
     `boot.loader.grub.device = mkVMOverride cfg.bootLoaderDevice` (prio 10, bat le
     `mkForce` du cogitator). Correctif : `virtualisation.bootLoaderDevice = "/dev/vda"`.
  3. (le troisième correctif a abouti — boot vert.)
Résultats du spike reportés dans la section « Prémisses mesurées » du plan.

Pre-flight : décision 3 du plan (clés SSH) — le spike montre quatre **symlinks**
vers `/persist/etc/ssh/`, cibles inexistantes au moment de la mesure. La moitié
« mécanique » est réglée, la moitié « ça marche » reste à prouver par la séquence
deux boots. Les deux issues du résultat sont prévues dans le plan.

Pre-flight : aucun fichier de `relics/` ou `cogitator/` ne doit changer dans ce
chantier — vérifié contre la liste *Affected Files*.

Ruling (Step 1 + Step 2 fusionnés) : le plan les séparait (le proving, puis son
enregistrement), mais le proving n'est **vérifiable** qu'une fois l'attribut
`legacyPackages…provings.sarcophagus-kvm` présent — la solution de repli prévue
par le plan (sonde équivalente hors arbre) dupliquerait le fichier pour rien.
Un seul commit atomique, donc, avec les trois fichiers. Coût si c'est le mauvais
choix : nul, c'est une frontière de commit. Précédent dans le dépôt : le chantier
3-B, groupé pour la même raison.

Note : `nix build` sur un attribut de flake refuse un fichier non suivi par git
(« Path 'provings/sarcophagus-kvm.nix' … is not tracked »). `git add` avant le
premier build, pas après.

Step 1+2 : complete — proving **vert** du premier coup après `git add`.
`nix build .#legacyPackages.x86_64-linux.provings.sarcophagus-kvm` → exit 0,
`/nix/store/gpqjpzabdgaq8iiazqvkk12xzs8k534x-vm-test-run-sarcophagus-kvm`,
script en 63,15 s (deux boots : 30,7 s puis 29,3 s jusqu'à `multi-user.target`).

**La question ouverte de `provings/dreadnought.nix:175-182` est tranchée, et la
réponse est « ça marche ».** Les quatre `/etc/ssh/ssh_host_*` sont des liens
symboliques vers `/persist/etc/ssh/` (pas des bind mounts, d'où l'absence d'unité
de montage), sshd écrit à travers, et l'empreinte de `ssh_host_ed25519_key.pub`
est **identique avant et après le rollback**. Un sarcophage ne change donc pas
ses clés d'hôte à chaque reboot — ce n'est pas un second défaut de #89, et la
note de portée de `dreadnought` doit être corrigée (Step 4).
Step 4 : complete — note de portée de `dreadnought` corrigée sur trois points
(le « gagne contre tout » devient « par défaut, et voici l'échappatoire » ; la
question ouverte sur les clés SSH est remplacée par la mécanique amont + le
résultat mesuré ; le paragraphe de clôture nomme les deux bancs au lieu d'un).
`nix build …provings.dreadnought` → exit 0, toujours vert.
Step 3 : complete — doc EN+FR : ligne de couverture, coût de `just test` mis à
jour avec les chiffres **mesurés** (8 épreuves, 11 boots, 63 s pour celle-ci),
et une section « external-image pattern » qui table les cinq options du nœud avec
leur raison. `just docs-parity` → OK, `npm run build` → 90 pages, exit 0.

## Revue de clôture par contexte neuf (2026-10-17)

Sous-agent, diff `5a0c223..HEAD`, Review Focus verbatim. Aucun **Critical**. Il a
vérifié et validé les quatre modes d'échec du Review Focus (l'échappatoire
`mkForce {}` est réelle — `qemu-vm.nix:1397` ; la surcouche COW survit au
`shutdown()` et le contre-contrôle `/persist` est présent ; l'ordre
snapshot-puis-témoin est bon ; `git diff --name-only` ne touche aucun module,
donc aucun `drvPath` de consommateur ne bouge). Sa passe de discrimination sur
les huit sous-tests n'a trouvé **aucun** assert qui serait vert sans le code STC.

**Important 1 — retenu et corrigé.** « Four lines make it work » au-dessus de
**cinq** options, répété 4 fois (proving ×2, doc EN, doc FR). Erreur de ma main.
Risque concret : quelqu'un reprenant le patron pour #47 en laisse une — le plus
probablement `system.switch.enable`, la seule qui n'est pas une `virtualisation.*`.

**Important 2 — retenu, et sa correction était fausse.** Il affirmait que le
régime permanent est un *bind mount* : `@blank` étant pris avant les services
`persist-*`, le rollback effacerait les symlinks du boot 1, et `mount-file.bash`
trouverait alors une cible réelle. Raisonnement solide, mais c'est une lecture,
pas une mesure. Assert écrit, proving lancé : **rouge**, `findmnt` échoue au
boot 2. Relevé de diagnostic dans la VM :
  - `/etc/ssh/ssh_host_*` sont **toujours** des symlinks au boot 2, mtime `19:21`
    (= heure de build de l'image) là où `ssh_config` porte l'heure du boot ;
  - `vmpool/root@blank` **contient lui-même les symlinks** ;
  - les cinq unités `persist-*` sont vertes en n'ayant rien fait.
Cause racine trouvée dans l'amont : `nixos.nix:477-480` déclare
`system.activationScripts."persist-files"`, le **même** `mount-file.bash`, et
`nixos-install` l'exécute dans le builder d'image où `/persist` est vide → les
liens sont cuits dans l'image, donc dans `@blank`, donc restaurés à chaque
rollback, et le script prend ensuite sa branche 1 (« already links to target »).
Ruling : ma prose d'origine (« symlinks vers /persist, sshd écrit à travers »)
était **exacte** ; ce qui manquait, aux deux, c'est *pourquoi* le lien survit.
Nouveau sous-test « boot 2: and here is why the host key survives at all » qui
monte `@blank` en lecture seule et y lit le lien — vu rouge puis vert.

**Important 3 — écarté, argumenté.** Il jugeait « /etc/machine-id a une unité de
montage » comme conflant deux choses. C'est littéralement vrai :
`etc-machine\x2did.mount` apparaît dans `systemctl list-units --type=mount`,
systemd synthétisant une unité pour toute entrée de `mountinfo` — mesuré dans le
spike. Il valide lui-même le « special branch ». Passage resserré au passage par
la réécriture du point 2.

**Minor 4 — corrigé** (ligne non rewrappée dans la doc EN, dans un paragraphe
que je réécrivais déjà).

**Minor 5 — différé, décision utilisateur.** La surcouche COW
(`tempfile(delete=False)`) n'est jamais supprimée. `delete=False` est nécessaire
— elle doit survivre au `shutdown()` — et le bac à sable du builder jette le
`TMPDIR`, donc l'effet est nul en CI et petit en interactif. Pas touché.

Vérifications après la passe : `nix build` des provings `sarcophagus-kvm` **et**
`dreadnought` → exit 0 (65,84 s et 25,65 s de script), `just docs-parity` → OK,
`npm run build` → 90 pages. Chiffre de la doc remis à la valeur mesurée (66 s).
