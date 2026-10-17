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
