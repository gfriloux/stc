# Changelog

All notable changes to STC are documented here.
Releases follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Bug Fixes

- drop the fictional v3.0 (January 2027) deprecation timeline ([`6fd9024`](https://github.com/gfriloux/stc/commit/6fd90245f2da189f17d91efa7adcc489411e3906))

### Documentation

- track core project docs (DESIGN, CLAUDE, PROCEDURE_PLANS, SECURITY, MIGRATION) ([`98ddf69`](https://github.com/gfriloux/stc/commit/98ddf692e9cdb253904a0a825651290085c59d2a))
## [0.6.0] — 2026-07-16

### Features

- **relics-hardening**: absorb exampleHost hand-rolled hardening into relics ([`00a1bea`](https://github.com/gfriloux/stc/commit/00a1bea68a553087920efa5c62abcc36d110fa56))
- **cogitator-workstation**: add hardened workstation profile ([`ad5f525`](https://github.com/gfriloux/stc/commit/ad5f525d76dfee7485de1ec7ed11ea25af8b4936))

### Testing

- **provings**: add docker-server wiring proving ([`875375b`](https://github.com/gfriloux/stc/commit/875375b8a06641d0516839f6b384a1adbfd1890c))
## [0.5.0] — 2026-07-13

### Bug Fixes

- **purity-seals**: do not use --exclude by default ([`c011bde`](https://github.com/gfriloux/stc/commit/c011bde521aa3e5d66757d8d66468119a0ea08e0))

### Refactoring

- **relics-docker**: make notify transport-agnostic (drop hardcoded ntfy) ([`645b01f`](https://github.com/gfriloux/stc/commit/645b01f16dd686dfaf6eb2a35a2308416152f023))
- **relics-docker**: require explicit image on infra relics (no pinned defaults) ([`f23853d`](https://github.com/gfriloux/stc/commit/f23853d0da4b492cfd15fd66da4e3fd1108e5447))
## [0.4.0] — 2026-07-04

### Bug Fixes

- **enginseer**: set catppuccin.autoEnable explicitly ([`e34855c`](https://github.com/gfriloux/stc/commit/e34855c53cb673428db43a318dc4405a98eaa11f))

### Documentation

- **provings**: document the provings pillar (EN + FR) ([`b56b568`](https://github.com/gfriloux/stc/commit/b56b568f12ede26a51967ec24f35042e7c847dc6))
- **hardening**: annotate rules with ANSSI-BP-028 references ([`b549ea4`](https://github.com/gfriloux/stc/commit/b549ea4ed9d8aeea10e9e0018d404ee2345b0a68))
- **reference**: add ANSSI-BP-028 compliance matrix (EN + FR) ([`4483a14`](https://github.com/gfriloux/stc/commit/4483a1488b867b59d71441fe3e326e393e10d5f7))

### Testing

- **provings**: add hardening nixosTest and provings pillar wiring ([`9f631f0`](https://github.com/gfriloux/stc/commit/9f631f090dee2dd207fca889916b108ea5524ec3))
## [0.3.0] — 2026-07-03

### Documentation

- **forge**: document Purity Seals, remove nix-checks references ([`90124ec`](https://github.com/gfriloux/stc/commit/90124eccf08e2106282e1dfa40f56f67fe8b0f1a))

### Features

- **forge-purity-seals**: internalize CI checks as stc.lib.puritySeals ([`bab9741`](https://github.com/gfriloux/stc/commit/bab9741d065c53ed538644d2bff3c308def2cd9f))

### Refactoring

- **forge-templates**: consume stc.lib.puritySeals instead of stc.inputs.nix-checks ([`b13e765`](https://github.com/gfriloux/stc/commit/b13e7658adc0cdeb267fe59e6379c03d1e22278f))
## [0.2.2] — 2026-06-08

### Bug Fixes

- **hardening-filesystem**: fire hidepid warning on Plasma (|| not or) ([`3a85e09`](https://github.com/gfriloux/stc/commit/3a85e0947f54a630cad11a34753c5736a0f9f2d9))
- **relics-aws**: derive partition separator for Xen devices ([`f0339de`](https://github.com/gfriloux/stc/commit/f0339deb95ee25d436d62a53d23d25ee9ff61ed7))

### Documentation

- **cogitator-sarcophagus**: clarify disko block is descriptive, fix partition comments ([`a621d67`](https://github.com/gfriloux/stc/commit/a621d67d706a24250c8d707aa13714b031c07bd0))
- correct ssh keepalive semantics, traefik dashboard loopback, local-vm drive path ([`4706dbc`](https://github.com/gfriloux/stc/commit/4706dbc9d3425a727099b0d11481ad00f817edec))
- **docker-notify**: note that a persistently-unhealthy container stops ([`84f7ff4`](https://github.com/gfriloux/stc/commit/84f7ff417bdf9b55480f318965e754056eed798a))

### Features

- **cogitator-vm**: make user lingering opt-in (default true) ([`bca293b`](https://github.com/gfriloux/stc/commit/bca293b7dabcf79421becfee868758fc878a3db3))
- **hardening-network**: make reverse-path filter mode configurable ([`eede806`](https://github.com/gfriloux/stc/commit/eede8062c0b42103f8c727833c943aedf3403d05))
- **hardening-kernel**: restrict ptrace via yama.ptrace_scope ([`5b97fe7`](https://github.com/gfriloux/stc/commit/5b97fe7138dff118fa988fcff0e9a8293c41fea2))
- **hardening-ssh**: assert OpenSSH supports the post-quantum kex ([`04aa188`](https://github.com/gfriloux/stc/commit/04aa188d8692ae25332683eb718bed2a5e52d5ba))

### Refactoring

- **cogitator-sarcophagus-kvm**: declare fileSystems explicitly like aws ([`91cce27`](https://github.com/gfriloux/stc/commit/91cce270e25defdf290f4ff386feb5668e9e93dc))
- **relics-zfs**: guard autoSnapshot on dataset existence instead of || true ([`e0abebf`](https://github.com/gfriloux/stc/commit/e0abebf624462d98c75de269d862381d868b1fb1))
## [0.2.1] — 2026-06-06

### Bug Fixes

- **relics-vaultwarden**: set DOMAIN for proxy/WebAuthn correctness ([`70ba5a2`](https://github.com/gfriloux/stc/commit/70ba5a2d1635f0ee57ace3721f9eb366b5f25524))
- **relics-hardening**: PQ SSH key exchange and hidepid/desktop warning ([`aa27640`](https://github.com/gfriloux/stc/commit/aa276402a050fe5d82058cb6a2511714ee119f20))
- **relics-docker-notify**: match health-watch label value, not presence ([`65dff71`](https://github.com/gfriloux/stc/commit/65dff714ff359c6260b4ffba7199b713616e549c))
- **lib-docker**: drop destructive ExecStop from mkNetwork ([`c980744`](https://github.com/gfriloux/stc/commit/c980744ceaef2d166905e0626353505c2d9f4788))
- **relics-docker**: reliable web network, soft crowdsec dep, USR1 logs, digest pin ([`ad2d365`](https://github.com/gfriloux/stc/commit/ad2d3655ed9db0ddabe536d7c2101a33eeee3d83))
- **relics-aws**: run growpart as a boot oneshot, not an activation script ([`f14d5dd`](https://github.com/gfriloux/stc/commit/f14d5dda0b35d9f8d1dd4591e3d5670e181fe00c))

### Documentation

- describe CrowdSec as IDS/IPS, not WAF, in indexes and README ([`76c3b7e`](https://github.com/gfriloux/stc/commit/76c3b7e911f4075401236995cbc06cb4f471209c))
- **relics-traefik**: explain native vs Docker deployments and ACME challenge ([`68456c3`](https://github.com/gfriloux/stc/commit/68456c3ab706df27d8529d4fcc736767f125f9c7))
- **cogitator-sarcophagus-kvm**: fix contradictory EFI/BIOS header comment ([`07d59db`](https://github.com/gfriloux/stc/commit/07d59dbfca9f67cd2323b57fd5e214fa7358db10))
- **schematics-local-vm**: warn on placeholder hostId and password ([`7e09f1e`](https://github.com/gfriloux/stc/commit/7e09f1e76156d667de24c266b79255d78537a36a))
## [0.2.0] — 2026-06-06

### Bug Fixes

- **relics**: impermanence: zfs rollback will now work ([`c647cda`](https://github.com/gfriloux/stc/commit/c647cda52adb343827b055d39d2f3766eb65040e))
- **relics**: mount Docker socket read-only in Traefik container ([`b4b9a56`](https://github.com/gfriloux/stc/commit/b4b9a5634da8042a67bd250e9ed009569d1afb01))
- **relics**: disable Vaultwarden signups and invitations by default ([`80b67e3`](https://github.com/gfriloux/stc/commit/80b67e393bf7f157d600893d8dd2e4d35e6e256d))
- **relics**: replace core_pattern /bin/false with systemd.coredump.enable = false ([`bea7c8d`](https://github.com/gfriloux/stc/commit/bea7c8de74c7be803723a2e7336f440823a65fa0))
- **relics**: remove no-op kernel.unprivileged_userns_clone sysctl and gaming option ([`f26cd36`](https://github.com/gfriloux/stc/commit/f26cd363122151711abfe9a0c58e56f201626007))
- **relics**: use %p instead of %n in OnFailure to avoid double .service suffix ([`9cc9fbf`](https://github.com/gfriloux/stc/commit/9cc9fbf888e9da18b25784c5c51ed9d64662f636))
- **relics-traefik**: drop sensitive headers from native access log ([`acdaa52`](https://github.com/gfriloux/stc/commit/acdaa522eb541c4c1ff49511cfa16ffe20dd6969))
- **relics-docker-traefik**: order docker-network-web before traefik ([`0ff42f4`](https://github.com/gfriloux/stc/commit/0ff42f4e0ca3316454f02831a545cf290280d74a))
- **relics-docker-notify**: target the real systemd unit for watched containers ([`b804e68`](https://github.com/gfriloux/stc/commit/b804e6887a8e131be664a0f320d3ad731cf1d01b))
- **relics**: make persistence conditional on impermanence and honor persistPath ([`7e1b80a`](https://github.com/gfriloux/stc/commit/7e1b80a2f16b27b82040c6837c3d125e380b1c1f))
- **relics-docker-traefik**: guard crowdsec option reference for standalone use ([`0690f9b`](https://github.com/gfriloux/stc/commit/0690f9b370fd0cd42aed94674122175a3dd50595))
- remove unused bindings flagged by deadnix ([`d9a56d0`](https://github.com/gfriloux/stc/commit/d9a56d025fcd910d00cc2d3432a5fe301d670324))
- **relics-vaultwarden**: remove deprecated WEBSOCKET_ENABLED ([`ed1281c`](https://github.com/gfriloux/stc/commit/ed1281ca729e515f71db6a9a91462b1cab570fbb))
- **relics-zfs**: move ZED debug log out of world-readable /tmp ([`b59d5e7`](https://github.com/gfriloux/stc/commit/b59d5e7d56a1050f7765c4d8a8bc2771d4620463))
- **relics-docker-traefik**: disable dashboard by default and fix description ([`a0c1a95`](https://github.com/gfriloux/stc/commit/a0c1a9558a6ea0884bb8ef8f08853be27a3fbab5))

### Documentation

- **all**: fix width of tables ([`c02c6b5`](https://github.com/gfriloux/stc/commit/c02c6b5d25758dc0c4a57b6d5db11fee4a4c09ca))
- **all**: update namespaces ([`9c5a4a6`](https://github.com/gfriloux/stc/commit/9c5a4a64313504754c6011bab5737d7e8b2a77e2))
- **all**: better. ([`936a8ec`](https://github.com/gfriloux/stc/commit/936a8ece38f391e76e905f888a14ee9e951bbb79))
- **all**: disable Vaultwarden signups and invitations by default ([`3ab225e`](https://github.com/gfriloux/stc/commit/3ab225edbaa23b26b31c2ef8a78276bb8f0fcd64))
- **relics**: remove no-op kernel.unprivileged_userns_clone sysctl and gaming option ([`1441a76`](https://github.com/gfriloux/stc/commit/1441a76c6a6d6af633b1267237b3e75cc4d1f34f))
- add root README ([`2731349`](https://github.com/gfriloux/stc/commit/273134929d6643b1e7f7b6a5d61499f47531b931))
- **relics-aws**: document random.trust_cpu trade-off ([`99404b5`](https://github.com/gfriloux/stc/commit/99404b541a87ccf7074aada116ad90915e430bce))
- **relics-docker-notify**: warn about public ntfy.sh default ([`707ad44`](https://github.com/gfriloux/stc/commit/707ad449e1789b789ff2ac76b8e05ba0bc26658b))
- **schematics-dreadnought**: strengthen NOPASSWD/hostId warnings ([`8d4355e`](https://github.com/gfriloux/stc/commit/8d4355e3117161e18f9928e9203b2b5294f730f8))
- **schematics**: document per-schematic flake.lock trade-off ([`c3d023f`](https://github.com/gfriloux/stc/commit/c3d023f9c1015e27f205ea2d9638fb0ff0b7f00e))
- use canonical stc.relics.* namespace in examples ([`db2bb1a`](https://github.com/gfriloux/stc/commit/db2bb1ab85bd0159ed043ae4f6824c993a093488))

### Features

- **relics**: add docker-socket-proxy and route Traefik through it ([`58cd655`](https://github.com/gfriloux/stc/commit/58cd6551495de925f8e6f3307ddd18f705c1470d))
- **cogitator-vm**: make docker opt-in (default false) ([`ad7669c`](https://github.com/gfriloux/stc/commit/ad7669c9107a7cf8bd7c89294d47fe9b9f81ca12))
- **relics-zfs**: add kernel selection, default to LTS ([`322ea10`](https://github.com/gfriloux/stc/commit/322ea1002d391047ba6dc35662675c39e183f2c1))

### Refactoring

- **all**: stabilize namespace ([`6bae1b7`](https://github.com/gfriloux/stc/commit/6bae1b787fb7b9558ddd85831f552e562e4d5dd2))
- apply statix fixes and disable repeated_keys lint ([`83875cf`](https://github.com/gfriloux/stc/commit/83875cfdb9fd00e4d2ad57b62e431d1d49f7e65b))
- **relics-docker-traefik**: rename ACME resolver to letsencrypt ([`50821ec`](https://github.com/gfriloux/stc/commit/50821ec70709c4ae3a67b63cade112242cf0a5f3))
## [0.1.0] — 2026-06-02

### Documentation

- **all**: fix base url ([`de7a7cf`](https://github.com/gfriloux/stc/commit/de7a7cf5090b96307bc3abdede599b8a10c52c37))
- **all**: update style ([`7a5b15b`](https://github.com/gfriloux/stc/commit/7a5b15b5710c7fc9013056c735af4df024f77a6b))
- **all**: document new relics/cogitators ([`83a469d`](https://github.com/gfriloux/stc/commit/83a469d88cff415c97e4123f5affb905e754fd1d))
- **all**: add plasma-manager ([`d80ae9b`](https://github.com/gfriloux/stc/commit/d80ae9bb6a1e8d4e0fc2aa5748984cc32d96c8ad))
- **all**: updates ([`ebdaa6e`](https://github.com/gfriloux/stc/commit/ebdaa6ea893907a64fe5aae269956c30abb55228))
- **all**: document new options ([`8a2b020`](https://github.com/gfriloux/stc/commit/8a2b0204861a532984c39bf41128b530839cba54))
- **all**: fix links for github ([`80a9588`](https://github.com/gfriloux/stc/commit/80a95888488957b8f9f262c2375c6e7e7535afb4))
- **all**: add new cogitators/schematics ([`05ccaab`](https://github.com/gfriloux/stc/commit/05ccaabb26ae5eb4ab2dca363d3f4e7dd202c3a2))

### Features

- **all**: first version ([`22eebca`](https://github.com/gfriloux/stc/commit/22eebcab468a44894e959bddfcf43d06e8916d3e))
- **all**: add relics/cogitators for my desktop PC ([`3b33715`](https://github.com/gfriloux/stc/commit/3b33715f63a2a408427b0118077e920aec8b3aaf))
- **all**: add plasma-manager ([`6c0ec65`](https://github.com/gfriloux/stc/commit/6c0ec65bf4d7b6b8b504469a375a88d176aa3752))
- **all**: add packages ([`0eaae36`](https://github.com/gfriloux/stc/commit/0eaae366bf55dea9cdfe9dcc33a01c653d95741b))
- **all**: add options ([`f502b03`](https://github.com/gfriloux/stc/commit/f502b0327fadc3f88995873fd459d14a38fc8b14))
- **all**: new cogitators ([`8a5cf4a`](https://github.com/gfriloux/stc/commit/8a5cf4a1d914cf5d2fc056837e8a8fc279e548a7))

