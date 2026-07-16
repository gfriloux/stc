# Migration Guide — `stc.*` → `stc.relics.*`

## What changed

Since `v0.2.0`, relics expose their options under `stc.relics.*` instead of the
flat `stc.*` used by the first release (`v0.1.0`).

| Layer | Before (`v0.1.0`) | After (`v0.2.0`+) |
|-------|--------------|---------------|
| Relics | `stc.boot`, `stc.zfs`, `stc.traefik`, … | `stc.relics.boot`, `stc.relics.zfs`, `stc.relics.traefik`, … |
| Cogitators | `stc.cogitator.vm`, `stc.cogitator.hardening`, … | unchanged |

Cogitators are **not affected** — they were already under `stc.cogitator.*`.

The only breaking change concerns configurations that use **relics directly**.

## Timeline

| Version | Behaviour |
|---------|-----------|
| **`v0.2.0`+** (current) | `stc.*` still works, emits a **NixOS deprecation warning** at eval time |
| **`v1.0.0`** (next major) | `stc.*` removed entirely |

Both namespaces coexist for the whole `0.x` series — migrate at your own pace;
each migrated option silences its warning immediately.

## Migration patterns

### System relics

```nix
# Before
stc.boot.enable = true;
stc.zfs = {
  enable = true;
  scrubInterval = "weekly";
  autoSnapshot = {
    enable = true;
    poolName = "rpool";
    daily = 7;
  };
};
stc.networking = {
  enable = true;
  domain = "home.local";
};
stc.impermanence = {
  enable = true;
  poolName = "rpool";
  extraDirectories = [ "/var/db/sudo/lectured" ];
};
stc.aws = {
  enable = true;
  poolName = "rpool";
};

# After
stc.relics.boot.enable = true;
stc.relics.zfs = {
  enable = true;
  scrubInterval = "weekly";
  autoSnapshot = {
    enable = true;
    poolName = "rpool";
    daily = 7;
  };
};
stc.relics.networking = {
  enable = true;
  domain = "home.local";
};
stc.relics.impermanence = {
  enable = true;
  poolName = "rpool";
  extraDirectories = [ "/var/db/sudo/lectured" ];
};
stc.relics.aws = {
  enable = true;
  poolName = "rpool";
};
```

### Hardening relics

```nix
# Before — individual relics
stc.hardening.kernel.enable = true;
stc.hardening.kernel.gaming = true;
stc.hardening.network.enable = true;
stc.hardening.filesystem = {
  enable = true;
  shmSize = "2G";
  gaming = true;
};
stc.hardening.ssh.enable = true;

# After — individual relics
stc.relics.hardening.kernel.enable = true;
stc.relics.hardening.kernel.gaming = true;
stc.relics.hardening.network.enable = true;
stc.relics.hardening.filesystem = {
  enable = true;
  shmSize = "2G";
  gaming = true;
};
stc.relics.hardening.ssh.enable = true;
```

> **Note:** If you use the `cogitator-hardening` profile, no change needed:
> `stc.cogitator.hardening.enable = true;` is unchanged.

### Desktop and hardware relics

```nix
# Before
stc.amdGpu.enable = true;
stc.pipewire.enable = true;
stc.plasma6 = {
  enable = true;
  keyboardLayout = "fr";
};
stc.yubikey.enable = true;   # system relic

# After
stc.relics.amdGpu.enable = true;
stc.relics.pipewire.enable = true;
stc.relics.plasma6 = {
  enable = true;
  keyboardLayout = "fr";
};
stc.relics.yubikey.enable = true;
```

### Service relics (Traefik, Vaultwarden)

```nix
# Before
stc.traefik = {
  enable = true;
  email = "admin@example.com";
};
stc.vaultwarden = {
  enable = true;
  hostname = "vault.example.com";
  signupsDomains = [ "example.com" ];
};

# After
stc.relics.traefik = {
  enable = true;
  email = "admin@example.com";
};
stc.relics.vaultwarden = {
  enable = true;
  hostname = "vault.example.com";
  signupsDomains = [ "example.com" ];
};
```

### Docker stack relics

```nix
# Before
stc.docker.traefik = {
  enable = true;
  acme.email = "admin@example.com";
  dataDir = "/srv/docker/traefik";
};
stc.docker.crowdsec = {
  enable = true;
  dataDir = "/srv/docker/crowdsec";
  envFile = config.sops.secrets."crowdsec/env".path;
};
stc.docker.notify = {
  enable = true;
  ntfy.topicFile = config.sops.secrets."ntfy/topic".path;
};

# After
stc.relics.docker.traefik = {
  enable = true;
  acme.email = "admin@example.com";
  dataDir = "/srv/docker/traefik";
};
stc.relics.docker.crowdsec = {
  enable = true;
  dataDir = "/srv/docker/crowdsec";
  envFile = config.sops.secrets."crowdsec/env".path;
};
stc.relics.docker.notify = {
  enable = true;
  ntfy.topicFile = config.sops.secrets."ntfy/topic".path;
};
```

### Home Manager relics

```nix
# Before
stc.gui.kitty.enable = true;
stc.gui.ghostty.enable = true;
stc.gui.zen-browser.enable = true;
stc.plasmaManager.enable = true;
stc.yubikey.enable = true;   # home relic

# After
stc.relics.gui.kitty.enable = true;
stc.relics.gui.ghostty.enable = true;
stc.relics.gui.zen-browser.enable = true;
stc.relics.plasmaManager.enable = true;
stc.relics.yubikey.enable = true;
```

## How to detect affected configurations

```bash
grep -r "stc\." /path/to/your/config --include="*.nix" \
  | grep -v "stc\.relics\." \
  | grep -v "stc\.cogitator\."
```

Any match is a path that needs migration.

## FAQ

**Are the schematics affected?**
The bundled schematics (`local-vm`, `aws-ami`, `dreadnought`) use cogitator profiles only — they are not affected.

**What about cogitators that reference relics internally?**
Cogitators already updated to use `stc.relics.*` internally. Consumer configs that set cogitator options (`stc.cogitator.*`) are not affected.

**Can I migrate gradually?**
Yes. Both namespaces coexist for the whole `0.x` series. Migrate module by module — each migrated option silences its warning immediately.

**Will the warnings show up in CI?**
Yes, `nix flake check` outputs warnings to stderr. They do not fail the build in the `0.x` series.
