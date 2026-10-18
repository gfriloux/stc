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

## Step 1 — l'épreuve et son enregistrement

Ruling (avant écriture) : le nœud du plan portait
`impermanence.extraDirectories = ["/var/lib/stc-proving"]`, recopié du patron
KVM. **Retiré** : la décision 4 dit que la persistance n'est pas réassertée ici,
donc l'option serait de la configuration morte — posée et jamais lue. Coût si
c'est le mauvais choix : nul, c'est une ligne de nœud.

Trois tours de banc, chacun avec sa cause lue avant correctif. L'image construit
et démarre du premier coup (le patron image externe de v0.15.0 a tenu tel quel) :
`multi-user.target` en 30,7 s, `is-system-running` → `running`.

1. **`/boot` rouge** — `findmnt -no SOURCE /boot` rend `/dev/vda2`, pas
   `/dev/disk/by-label/ESP`. Cause : `findmnt` résout vers le nœud de
   périphérique du noyau, pas vers le chemin que le cogitator déclare. Ma
   prémisse d'assert était fausse, pas le produit. Corrigé en deux lectures :
   `FSTYPE` vaut `vfat`, **et** `readlink -f /dev/disk/by-label/ESP` doit rendre
   le périphérique dont `/boot` est monté.
   **Fait faux que j'avais écrit et qui a été réfuté au passage** : mon
   commentaire présentait ce `/boot` comme « là où le cogitator AWS diffère du
   KVM ». Faux — `cogitator/nixos/sarcophagus-kvm.nix:114` déclare un `/boot`
   **identique au byte**. Le commentaire dit maintenant ce qui est vrai : les
   deux cogitators portent chacun leur copie de la déclaration, et c'est
   précisément pour ça que l'assert a sa place ici (une régression dans la copie
   AWS ne serait pas attrapée par l'épreuve KVM, et réciproquement).

2. **`xen_netfront` non chargé** — assert naïf « les deux pilotes sont chargés »,
   rouge. Diagnostic lancé avant toute correction, et il a sorti la cause exacte :
   `modprobe: ERROR: could not insert 'xen_netfront': No such device` (pas de bus
   paravirt Xen sur KVM), tandis que `ena` s'insère sans problème (pilote PCI
   ordinaire qui ne trouve simplement aucun périphérique). Et surtout :
   `systemd-modules-load` journalise `Failed to insert module 'xen_netfront'`
   **puis finit avec succès** et reste `active` — ce qui explique pourquoi le
   boot est `running` et non `degraded`.
   L'assert a été **réécrit plus fort** plutôt qu'affaibli : les deux pilotes sont
   *demandés* (`/etc/modules-load.d/nixos.conf`), celui qui peut se charger l'est,
   et l'unité est verte malgré l'autre. C'est la propriété qui permet à une seule
   AMI de servir Nitro **et** Xen, et elle casserait si la relique déplaçait ces
   modules dans `boot.initrd.kernelModules`. Délibérément **pas** « les deux sont
   chargés », qui n'est vrai que sur un matériel que ce banc ne peut pas être.

3. **Taille du pool journalisée** — un `print` permanent a été ajouté : le seuil
   de l'assert est un plancher, et un run qui le franchit de justesse veut dire
   que le banc a changé.

Verdict du banc, l'assertion phare : **le pool passe de ~4 Gio à 6,75 Gio**
(image de 4096 Mio, disque virtuel de 8 Gio), `stc-grow-pool` va au bout. Le
chemin de croissance EBS n'avait aucune couverture avant ce commit —
`dreadnought` ne lit que la chaîne du script, et le disque du KVM fait la taille
de son image.

Huit subtests verts. Script en **32,33 s** dont 31,38 s d'attente de
`multi-user.target`, image construite dans sa propre VM avant le test.

Gate d'innocuité (PF-4) : les trois `drvPath` de schematics sont **identiques**
à ceux relevés avant le chantier. `just ci` vert. `git diff --name-only` ne
contient aucun chemin sous `relics/`, `cogitator/` ou `schematics/`.

## Step 2 — la doc EN + FR

Quatre endroits, comme prévu : ligne de table de couverture, paragraphe de coût
(huit/onze → **neuf/douze**, avec les 32 s mesurés et non estimés), la phrase
« This is the pattern #47 should reuse » devenue le constat de la reprise avec
**les deux seules différences** nommées, et une note de portée qui dit ce que
l'épreuve a *levé* (import du pool, montages, périphérique de boot, croissance)
et les **trois** trous qui restent — console série, point d'NTP AWS,
`boot.zfs.devNodes` — chacun avec la mesure qui le justifie.

Mineur drive-by, dans les deux langues : la section unfree disait « les **cinq**
autres épreuves gardent un `drvPath` identique au byte ». Le compte était déjà
périmé avant ce chantier et le serait à chaque ajout → remplacé par « les autres
épreuves ». Pas de chiffre qui se périme.

`just docs-parity` vert, `just docs-build` vert (90 pages).

## Passe de relecture avant commit — deux affirmations de ma prose corrigées

Les deux trouvées en relisant mes propres commentaires, pas par un gate :

1. J'avais écrit, dans le commentaire du nœud, que `growpart` sur le périphérique
   absent « sort ≥2 » — **inféré, pas mesuré**. Mesuré depuis :
   `growpart /dev/nonexistent-disk-xyz 3` → **rc=2**, et la relique ne tolère que
   `rc=1`, donc `stc-grow-pool` échoue bien. L'affirmation était juste et elle est
   maintenant adossée à une commande. (Premier essai trompeur : sur cette machine
   `/dev/nvme0n1` **existe**, donc le bac à sable a rendu `rc=1` pour
   « Permission denied » — un tout autre mode de défaillance. C'est ce qui a
   failli faire consigner un faux fait dans l'autre sens.)
2. Le commentaire de `/boot` rattachait le défaut `ebsPartition = 3` au fait que
   le `/boot` est du FAT nu. Imprécis : la vraie raison est la disposition en
   trois partitions (bios_grub(1), ESP(2), ZFS(3)), c'est-à-dire que le ZFS est la
   troisième. Reformulé.

Note de discipline pour la suite du lot : l'arbre git sale fait partie du chemin
de source du flake, donc **toute** édition d'un fichier du dépôt — y compris ce
ledger — invalide les dérivations des neuf épreuves. Le `just test` de gate doit
donc être lancé une fois l'arbre figé, pas en parallèle de l'écriture. Perdu un
run complet à l'apprendre.
