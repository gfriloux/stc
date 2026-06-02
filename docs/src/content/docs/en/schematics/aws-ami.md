---
title: aws-ami
description: A NixOS AMI for AWS EC2 with ZFS, impermanence, and hardening.
---

**Source:** `schematics/aws-ami/`

A NixOS AMI image for AWS EC2, with ZFS storage, impermanence, and full hardening.

This schematic uses [cogitator-sarcophagus-aws](/stc/en/cogitator/sarcophagus-aws/),
which embeds the disk layout, AWS platform configuration, GRUB override, and raw
image builder — no separate `disko` import or `image.nix` module required.

Instances deployed from this AMI are intended to be managed with
[cogitator-dreadnought](/stc/en/cogitator/dreadnought/).

## Prerequisites

### Local setup

- Nix with flakes enabled
- AWS CLI configured (`aws configure`)

### AWS one-time setup

1. Create an S3 bucket for image uploads
2. Create the `vmimport` IAM role with the permissions from the [AWS VM Import documentation](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html)

### Before building

In `flake.nix`, edit at minimum:

- `networking.hostId` — generate a unique value: `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
- `openssh.authorizedKeys.keys` — add your SSH public key

SSH password authentication is disabled by `cogitator-hardening`. Without an SSH
key, you will not be able to connect to the instance.

## Modules Used

| Module | Purpose |
|--------|---------|
| `stc.nixosModules.cogitator-sarcophagus-aws` | ZFS + impermanence + hardening + AWS platform + disk layout + raw image builder |

## Justfile Recipes

```bash
just update    # update flake inputs

just build     # builds result/nixos.root.img (raw format, ~5-10 minutes)
just run       # boot the image in QEMU/KVM for local testing
just ssh       # SSH into the local VM (port 2222)

just publish   # uploads to S3, imports snapshot, registers AMI
```

`publish` requires: `just build` completed, `AMI_BUCKET` set in the Justfile,
and AWS CLI configured.

The full publish flow:
1. Upload raw image to `s3://AMI_BUCKET/AMI_NAME.img`
2. Import as EC2 snapshot (`aws ec2 import-snapshot`)
3. Poll until the import completes
4. Register the snapshot as an AMI (`aws ec2 register-image`)

## Complete flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    stc = {
      url = "github:gfriloux/stc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, stc, ... }: {
    nixosConfigurations.aws-ami = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-sarcophagus-aws
        ({ ... }: {
          stc.cogitator.sarcophagus-aws = {
            enable = true;
            impermanence.extraDirectories = [ "/var/db/sudo/lectured" ];
          };
          networking.hostName = "aws-ami";
          networking.hostId = "cafebabe";  # replace with your own
          users = {
            mutableUsers = false;
            users.root.initialPassword = "changeme";
            users.admin = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              initialPassword = "changeme";
              openssh.authorizedKeys.keys = [
                # "ssh-ed25519 AAAA... you@host"
              ];
            };
          };
          security.sudo.wheelNeedsPassword = false;
          time.timeZone = "UTC";
          i18n.defaultLocale = "en_US.UTF-8";
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

:::caution[Change the hostId]
`networking.hostId = "cafebabe"` is a placeholder. Every ZFS machine must have a
unique hostId. Generate one: `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
:::

## See Also

- [cogitator-sarcophagus-aws](/stc/en/cogitator/sarcophagus-aws/) — full options reference for the image builder
- [cogitator-dreadnought](/stc/en/cogitator/dreadnought/) — profile for managing instances deployed from this AMI
- [relics-aws](/stc/en/relics/aws/) — the AWS platform relic
- [relics-impermanence](/stc/en/relics/impermanence/) — how the rollback works
