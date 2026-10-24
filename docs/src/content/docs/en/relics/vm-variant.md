---
title: VM Variant
description: Boot an STC-based host as a local QEMU VM, with its secret-, image- and pool-dependent parts neutralised.
---

**Module:** `stc.nixosModules.relics-vm-variant`

NixOS can boot any configuration as a local QEMU VM. This relic makes that
actually work for a host built from STC.

```bash
nix build .#nixosConfigurations.<host>.config.system.build.vm
./result/bin/run-<host>-vm
```

It is the missing gate between *it evaluates* and *I deployed it to production*:
a real boot, real systemd, real units, no risk. It matters most where a mistake
locks you out — a host reachable only over a VPN, or a change touching `sudo`,
`users` or `sshd`.

Three things stop a plain `system.build.vm` from coming up on an STC host, and all
three come from STC relics, so every consumer hits the same three and would write
the same workaround:

| Obstacle | Why it fails in a VM |
|----------|----------------------|
| Secrets | A host deriving its key from `/etc/ssh/ssh_host_ed25519_key` has no key in a fresh VM, so secret activation fails and everything depending on a secret path fails with it. |
| Containers | `oci-containers` units try to pull their images. A VM with no registry credentials, and often no outbound network, cannot. |
| ZFS / impermanence | The impermanence relic rolls a dataset back from an initrd service and the ZFS relic force-imports a root pool. In a VM there is neither the pool nor the snapshot. |

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.vmVariant.enable` | bool | `false` | Enable the VM variant wiring |
| `stc.relics.vmVariant.disableZfs` | bool | `true` | Turn `stc.relics.zfs` off inside the VM |
| `stc.relics.vmVariant.disableImpermanence` | bool | `true` | Turn `stc.relics.impermanence` off inside the VM |
| `stc.relics.vmVariant.disableContainers` | bool | `true` | Empty `virtualisation.oci-containers.containers` inside the VM |
| `stc.relics.vmVariant.rootPassword` | string or null | `null` | Plain-text root password, VM only |
| `stc.relics.vmVariant.skipActivationScripts` | list of strings | `[]` | Activation scripts whose body is emptied inside the VM |
| `stc.relics.vmVariant.maskUnits` | list of strings | `[]` | Systemd services disabled inside the VM |

## It Cannot Soften a Real Host

Everything this relic writes goes into `virtualisation.vmVariant`, and nowhere
else. Upstream builds that variant with `extendModules`, so it is a second,
separate evaluation whose only consumer is `system.build.vm`.

That is not a promise, it is a check. The production derivation is bit-identical
with the relic enabled:

```bash
nix eval .#nixosConfigurations.<host> --apply 'base: let
  on = base.extendModules {
    modules = [{ stc.relics.vmVariant.enable = true; }];
  };
in base.config.system.build.toplevel.drvPath
   == on.config.system.build.toplevel.drvPath'
# => true
```

Run it on your own host if you would rather not take our word for it. A relic
whose job is "turn off protections" invites exactly the wrong reading, which is
why this mechanism was chosen for that property rather than for convenience.

## What This VM Proves — and What It Does Not

| Proves | Does not prove |
|--------|----------------|
| The machine boots | Anything about your containers |
| systemd units start, and in the right order | Anything about your secrets |
| Users, groups and shells exist as declared | Anything about your storage layout |
| Network and DNS come up | That the production kernel works (see `disableZfs` below) |
| Firewall rules are what you think they are | That a real pool imports, or that a rollback behaves |

The three things it does not prove are exactly the three it switches off. A gate
that overstates its coverage is worse than no gate: treat a green VM boot as
*the wiring is sane*, not as *this is deployable*.

## Usage Example

```nix
# flake.nix
modules = [
  stc.nixosModules.relics-vm-variant
  ./configuration.nix
];

# configuration.nix
{
  stc.relics.vmVariant = {
    enable = true;

    # A way in without the host's key material — see the warning below.
    rootPassword = "vm";

    # Neutralise the secrets backend. STC does not know which one you use, so
    # name its activation script yourself:
    skipActivationScripts = ["setupSecrets"];               # sops-nix
    # skipActivationScripts = ["agenixInstall" "agenixNewGeneration"];  # agenix

    # For a backend that installs secrets from a unit instead:
    # maskUnits = ["sops-install-secrets"];
  };
}
```

:::caution[Without `rootPassword`, nobody can log in]
Neutralising the secrets backend also neutralises the authorized keys it
installs. A VM with no root password is then a VM you cannot get into — it boots
and you watch it from the outside.

`rootPassword` is deliberately not defaulted on: a password that leaked into a
non-VM path would be a liability. It is also not an exception to STC's
[`*File` secrets rule](/stc/en/architecture/) — the value never leaves the VM
variant, so it never reaches a real host. It is a test-bench parameter.
:::

## Why There Is No `disableSops`

STC is agnostic to the secrets backend: there is no sops or agenix module in this
repository, only the `*File` convention. A relic writing `sops.*` would hardcode
one backend — and would be a hard evaluation error for anyone who does not import
it, because the VM variant extends *your* module list, so the `sops` option only
exists if you brought it.

Hence the generic pair. `skipActivationScripts` empties a script's body rather
than removing the attribute, so other scripts declaring
`deps = [ "setupSecrets" ]` still resolve.

:::note[`maskUnits` fails open]
A unit name that matches nothing is silently accepted: it produces a disabled
unit and no error, so a typo goes unnoticed. There is no way to check a unit's
existence at evaluation time without breaking the legitimate case.
:::

## The Toggles Are the Escape Hatch

The relic writes with `lib.mkForce`. If you already override one of these inside
your own `virtualisation.vmVariant`, you get a priority conflict — and the way
out is the matching toggle, not a second `mkForce`:

```nix
stc.relics.vmVariant = {
  enable = true;
  disableZfs = false;   # keep the ZFS relic alive in the VM
};
```

That granularity is the point: you may want containers off but ZFS on.

:::note[`disableZfs` can change the kernel]
The ZFS relic picks a ZFS-compatible kernel. With its default `kernel = "lts"`
that is normally nixpkgs' default kernel, so nothing changes; with
`kernel = "latest"`, or when ZFS lags behind the default LTS, turning it off in
the VM means the VM runs a different kernel from production. Accepted on
purpose: the target of this gate is systemd wiring, not the storage driver. Set
`disableZfs = false` to keep the production kernel, at the cost of a pool import
that will fail.
:::

## Not To Be Confused With `provings/`

STC's [provings](/stc/en/provings/) are internal QA: each boots a VM
with a *cogitator* enabled and asserts it does what it claims. They test STC's
own modules. This relic is the other direction — it is what lets **you** boot
**your** host configuration.

No cogitator enables this relic. Deciding that a root password lands in your VM
builds is not a profile's call to make.

## See Also

- [Relics overview](/stc/en/relics/) — all relics
- [Impermanence](/stc/en/relics/impermanence/) — the rollback this relic disables in a VM
- [ZFS](/stc/en/relics/zfs/) — the pool import this relic disables in a VM
