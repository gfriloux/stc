# Ledger — plan: .claude/plans/v0.16.0/proving-sarcophagus-aws.md

Pre-flight (2026-10-18, avant toute branche) : lot « les épreuves, palier 2 »
choisi par l'utilisateur parmi quatre propositions (les trois autres :
#69+#59 survivabilité headless ; #86 audit des options à priorité normale ;
#37+#38 CIS sudo et NTP). Ordre du lot : #47, puis #83, puis #50.

Pre-flight : prémisses mesurées avant écriture du plan, aucune déduite.
  - `make-single-disk-zfs-image.nix` lignes 81-91 : le format `raw` donne le
    suffixe `.img`, donc `$out/nixos.root.img`. La surcouche COW se prend dessus
    avec `-F raw` — seule différence avec le patron KVM.
  - `relics/nixos/aws.nix` : `stc-grow-pool` lance
    `growpart /dev/${ebsDisk} ${ebsPartition}` et tolère `rc=1`, échoue à `rc≥2`.
    Avec le défaut `nvme0n1`, le périphérique n'existe pas dans une VM virtio →
    l'unité échoue → d'où la décision 2 (`ebsDisk = "vda"` sur le nœud).
  - `partSep` vaut `""` pour `"vda"` (la règle est « p seulement si le nom finit
    par un chiffre »), donc `/dev/vda3` — cohérent avec `ebsPartition = 3`, et
    ça exerce la branche Xen du calcul.
  - Le getty série est `lib.mkDefault true` depuis #45, donc plus de conflit dur
    avec l'instrumentation nixosTest : c'était le blocage historique.

Pre-flight : aucun fichier de `relics/`, `cogitator/` ou `schematics/` ne doit
changer dans ce chantier — vérifié contre la liste *Affected Files*, et contrôlé
par `git diff --name-only` à chaque commit (commande dans les steps).

PF-4 (2026-10-18) — `drvPath` des trois schematics relevés avant le premier
commit, pour que le gate d'innocuité soit une comparaison :
  - local-vm    : `k2mxsivc0k9ngdh84mfa8zvxfsmbm7zh-nixos-disk-image.drv`
  - aws-ami     : `2gymzw2pzynpa2c4ddcdk6212kkpqr9i-nixos-aws-ami.drv`
  - dreadnought : `1xnz47d7f96h4p2pyr7r2cxhfjak4n2g-nixos-system-dreadnought-26.11.20260923.4975466.drv`

PF-2 (2026-10-18) — orthographe et filetage vérifiés par éval, pas par lecture.
`stc.cogitator.sarcophagus-aws.ebsDisk = "vda"` rend
`growpart /dev/vda 3` puis `zpool online -e vmpool /dev/vda3` dans le script de
`stc-grow-pool`. Donc l'option traverse bien cogitator → relique, **et** la
branche `partSep = ""` (noms ne finissant pas par un chiffre, cas Xen) est
exercée. Le nœud ne pose pas `stc.relics.aws.ebsDisk`, sinon le filetage ne
serait plus ce qui est prouvé.

PF-3 (2026-10-18) — discrimination mesurée par `.nodes.machine` de
`runNixOSTest`, trois configurations comparées : nœud **nu**, nœud
`boot.supportedFilesystems = ["zfs"]` **sans STC**, nœud STC. Verdicts :

| Candidat | nu | zfs seul | STC | Verdict |
|---|---|---|---|---|
| `blacklistedKernelModules` | `[]` | `[]` | contient `xen_fbfront` | **retenu** |
| `kernelModules` | `atkbd,loop` | `+zfs` | `+ena,xen_netfront` | **retenu** (chargement runtime à mesurer au banc) |
| `services.udev.packages` | pas d'`amazon-ec2-utils` | idem | `amazon-ec2-utils-2.2.0` | **retenu** — règles nommées relevées dans le paquet, dont `70-ec2-nvme-devices.rules` |
| `nvme_core.io_timeout`, `random.trust_cpu` | absents | absents | présents | **retenus** |
| `boot.zfs.devNodes` | `/dev/disk/by-id` | `/dev/disk/by-id` | `/dev` | **écarté** — discriminant à l'éval mais pas observable au banc : la seule lecture runtime serait le chemin de store d'un script d'unité interpolé depuis la *même* éval, donc une tautologie ; et surtout un disque virtio **a** des entrées `by-id`, donc le défaut importerait le pool aussi bien. Le banc ne peut pas distinguer. |
| `networking.timeServers` | pool NixOS | pool NixOS | `169.254.169.123` | **écarté** — `services.timesyncd.enable` vaut `false` sur les **trois** nœuds (le socle de test l'éteint), donc aucun `/etc/systemd/timesyncd.conf` n'est rendu. Le point d'NTP AWS reste non couvert, comme pour `dreadnought`. |
| `systemd.services."serial-getty@ttyS0".enable` | `false` | `false` | `false` | **écarté** — l'instrumentation gagne le contest ordinaire depuis que la relique est en `mkDefault` (#45). Console série toujours non couverte. |
| `services.udisks2.enable` | `false` | `false` | `false` | **écarté** — déjà documenté comme non discriminant. |

Nuance relevée et **non résolue** sur `console=ttyS0,115200n8` : v0.14.0 avait
mesuré la chaîne non discriminante parce que le socle pose
`virtualisation.qemu.consoles`, qui arrive par le `-append` de qemu. Or sous le
patron image externe, `directBoot.enable = false` — le noyau est démarré par le
GRUB de l'image, donc la ligne de commande vient de `boot.kernelParams` seul
(mesuré : le nœud nu n'a que `console=ttyS0`, sans débit). La chaîne
*pourrait* donc discriminer ici. Établir le contraire demanderait de construire
une **seconde** image sans la relique, ce que le chantier ne paie pas : l'assert
n'est pas écrit, et la raison est dans l'en-tête du fichier.

PF-1 (2026-10-18) — le nom d'attribut produit par le step 1 et consommé par le
step 2 est `sarcophagus-aws` partout : fichier `provings/sarcophagus-aws.nix`,
attribut `legacyPackages.provings.sarcophagus-aws`, ligne de recette `test`,
ligne de la table de couverture. Pas de variante `sarcophagus_aws` ni `aws`.

---

<!-- Une ligne par step livré, chaque ruling, chaque mineur différé. -->
