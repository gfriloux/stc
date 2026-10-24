# Relic: VM Variant
# Makes an STC-based host boot as a local QEMU VM, with the parts that cannot
# work in a VM neutralised.
#
#   nix build .#nixosConfigurations.<host>.config.system.build.vm
#   ./result/bin/run-<host>-vm
#
# This is the missing gate between "it evaluates" and "I deployed it to
# production": a real boot, real systemd, real units, no risk. It matters most
# where a mistake locks you out — a host reachable only over a VPN, or a change
# touching sudo, users or sshd.
#
# READ THIS BEFORE ASSUMING THE WORST: every line below is written into
# `virtualisation.vmVariant`, and nowhere else. Upstream builds that variant with
# `extendModules` (nixos/modules/virtualisation/build-vm.nix), so it is a second,
# separate evaluation whose only consumer is `system.build.vm`. The production
# `system.build.toplevel` cannot change — and that is not a promise, it is
# checked by comparing drvPaths. A relic whose job is "turn off protections"
# invites exactly the wrong reading, which is why the mechanism was chosen for
# that property rather than for convenience.
#
# What the VM proves: boot, systemd units, users, network, shells, firewall.
# What it does NOT prove: containers, secrets, storage — the three things switched
# off below. A gate that overstates its coverage is worse than no gate.
#
# Two implementation facts that look like style but are not:
#
#   - The vmVariant definition is a *function* module so it receives the variant's
#     own `options`, and every toggle is guarded by an existence check. This is
#     mandatory, not defensive: `lib.mkIf false` does not protect against an
#     unknown option, and `stc.relics.zfs` only exists for a consumer who imports
#     that relic. Without the guard this relic would break every host that does
#     not import all of them.
#   - Nothing here names a secrets backend. STC is agnostic to it (there is no
#     sops or agenix module in this repository), so the escape is the generic
#     `skipActivationScripts` / `maskUnits` pair, with the per-backend recipes in
#     the documentation instead of in the code.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.vmVariant;
in {
  options.stc.relics.vmVariant = {
    enable = lib.mkEnableOption ''
      booting this host as a local VM with its secret-, image- and pool-dependent
      parts neutralised. Only ever writes into `virtualisation.vmVariant`, so the
      production build is untouched
    '';

    disableZfs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Turn `stc.relics.zfs` off inside the VM. There is no pool to import and no
        dataset to mount: upstream already replaces `fileSystems` wholesale in a
        VM build, so what this removes is the forced root-pool import and the
        pinned ZFS-compatible kernel.

        Note the consequence: with this on, the VM runs nixpkgs' default kernel.
        With `stc.relics.zfs.kernel = "lts"` that is normally the production
        kernel too; with "latest", or when ZFS lags behind the default LTS, it is
        not. Set it to `false` to keep the production kernel, at the cost of a
        pool import that will fail.

        Ignored when the ZFS relic is not imported.
      '';
    };

    disableImpermanence = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Turn `stc.relics.impermanence` off inside the VM. That relic rolls a
        dataset back from an initrd service; in a VM there is neither the pool nor
        the snapshot, so the service can only fail.

        Ignored when the impermanence relic is not imported.
      '';
    };

    disableContainers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Empty `virtualisation.oci-containers.containers` inside the VM. Container
        units try to pull their images, which a VM with no registry credentials
        and often no outbound network cannot do.

        The backend and any docker-network units stay, so the VM still proves that
        the Docker daemon comes up — it just runs nothing.
      '';
    };

    rootPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "vm";
      description = ''
        Plain-text root password for the VM, or `null` to set none.

        This is not an exception to STC's `*File` secrets rule: the value never
        leaves the VM variant, so it never reaches a real host. It is a test-bench
        parameter, and it is deliberately not defaulted on — a password that
        leaked into a non-VM path would be a liability.

        Leaving it `null` is a trap worth understanding: neutralising the secrets
        backend also neutralises the authorized keys it installs, so a VM with no
        root password is often a VM nobody can log into.

        Setting it forces `hashedPassword` and `hashedPasswordFile` to `null`
        inside the variant, because for an immutable user those two win over
        `password` in the upstream override order, and because upstream warns when
        several password options are set at once.
      '';
    };

    skipActivationScripts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["setupSecrets"];
      description = ''
        Activation scripts whose body is emptied inside the VM. This is how a
        secrets backend is neutralised without STC knowing which one you use: a
        host deriving its key from `/etc/ssh/ssh_host_ed25519_key` has no key in a
        fresh VM, so secret activation fails and everything depending on a secret
        path fails with it.

        - sops-nix: `["setupSecrets"]`
        - agenix: `["agenixInstall" "agenixNewGeneration"]`

        The body is emptied rather than the attribute removed, so that other
        scripts declaring `deps = [ "setupSecrets" ]` still resolve.
      '';
    };

    maskUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["sops-install-secrets"];
      description = ''
        Systemd services disabled inside the VM, for backends that install their
        secrets from a unit rather than from an activation script.

        A name that matches nothing is silently accepted — it produces a disabled
        unit and no error — so a typo here fails open. There is no way to check a
        unit's existence at evaluation time without breaking the legitimate case.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.vmVariant = {options, ...}: {
      config = lib.mkMerge [
        (lib.optionalAttrs (options.stc.relics ? zfs) {
          stc.relics.zfs.enable = lib.mkIf cfg.disableZfs (lib.mkForce false);
        })

        (lib.optionalAttrs (options.stc.relics ? impermanence) {
          stc.relics.impermanence.enable =
            lib.mkIf cfg.disableImpermanence (lib.mkForce false);
        })

        {
          virtualisation.oci-containers.containers =
            lib.mkIf cfg.disableContainers (lib.mkForce {});

          system.activationScripts =
            lib.genAttrs cfg.skipActivationScripts (_: {text = lib.mkForce "";});

          systemd.services =
            lib.genAttrs cfg.maskUnits (_: {enable = false;});

          users.users.root = lib.mkIf (cfg.rootPassword != null) {
            password = cfg.rootPassword;
            hashedPassword = lib.mkForce null;
            hashedPasswordFile = lib.mkForce null;
          };
        }
      ];
    };
  };
}
