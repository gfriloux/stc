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
