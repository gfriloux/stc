---
title: Enginseer
description: cogitator-enginseer — the full field-deployment CLI toolkit for a Techpriest.
---

**Module:** `stc.homeModules.cogitator-enginseer`

The Enginseer is the Adeptus Mechanicus operative sent into the field to maintain,
operate, and commune with machines of all kinds. This Home Manager profile assembles
the full CLI toolkit of a seasoned Enginseer: shell enhancements, dev tooling, git
rites, and aesthetic augmentations.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.enginseer.enable` | bool | `false` | Enable the Enginseer CLI profile |

## What It Configures

### Shell

- **fish** — primary shell with `oh-my-posh` prompt (Dracula theme)
- Shell aliases: `cat` → `bat`, `ping` → `prettyping`, `cp` → `xcp`

### Programs (Home Manager modules)

| Program | Role |
|---------|------|
| `atuin` | Shell history sync |
| `bat` | `cat` replacement with syntax highlighting |
| `btop` | Resource monitor |
| `delta` | Git diff pager (git integration enabled) |
| `direnv` + `nix-direnv` | Per-directory env activation, silent mode |
| `fzf` | Fuzzy finder |
| `git` | Version control |
| `gitflow-toolkit` | Git workflow helpers |
| `gh` | GitHub CLI (`git_protocol = ssh`) |
| `gpg` | GnuPG — key management and signing |
| `helix` | Modal text editor |
| `jq` | JSON processor |
| `lsd` | `ls` replacement with icons |
| `micro` | Simple terminal editor (opinionated settings, `nixd` LSP) |
| `nix-search-tv` | nixpkgs search with `television` integration |
| `rbw` | Bitwarden CLI |
| `television` | File search and preview |
| `television-ssh` | SSH host fuzzy search |
| `zellij` | Terminal multiplexer |
| `zoxide` | Smart `cd` replacement |

The `micro` editor ships with opinionated defaults (2-space soft tabs, ruler,
saved cursor, mouse) and an `nix:nixd` LSP binding (the `nixd` server is provided
below). Override any of them from your own home configuration.

### GPG agent

`services.gpg-agent` is enabled with fish integration. SSH authentication is **not**
delegated to gpg (`enableSshSupport = false`) — the consumer wires its own
`ssh-agent`. The pinentry defaults to `pinentry-curses`, a headless-safe choice so
the Enginseer works over TTY and on servers. It is set with `lib.mkDefault`, so
`cogitator-desktop` overrides it with a graphical pinentry (`pinentry-qt`).

### Packages

| Package | Purpose |
|---------|---------|
| `age` | File encryption |
| `alejandra` | Nix formatter |
| `aria2` | Multi-source download utility |
| `croc` | File transfer |
| `dive` | Docker image layer inspector |
| `doggo` | DNS lookup tool |
| `fastfetch` | System information display |
| `fd` | `find` replacement |
| `fzf-make` | Fuzzy Makefile task runner |
| `git-workspace` | Multi-repo workspace manager |
| `glow` | Markdown renderer |
| `gum` | Scripting UI components |
| `htop` | Interactive process viewer |
| `just` | Task runner |
| `ncdu` | Disk usage analyser |
| `nh` | `nixos-rebuild` / `home-manager` wrapper with better UX |
| `nix-output-monitor` | Better `nix build` output |
| `nix-tree` | Interactive Nix dependency graph explorer |
| `nixd` | Nix language server (LSP) for editor integration |
| `nvd` | NixOS generation diff — visualises changes between builds |
| `oh-my-posh` | Shell prompt engine |
| `ouch` | Painless compression / decompression |
| `p7zip` | Archive tool |
| `prettyping` | `ping` with graphs |
| `pv` | Pipe progress viewer |
| `pwgen` | Password generator |
| `rsync` | File synchronisation |
| `sops` | Secrets management |
| `unzip` | ZIP archive extraction |
| `viu` | Image viewer in terminal |
| `xcp` | `cp` with progress |

### Theme

Catppuccin **Frappe** flavour applied across all supported programs via the
`catppuccin` Home Manager module.

## Usage Example

```nix
# flake.nix
outputs = { nixpkgs, stc, home-manager, ... }: {
  homeConfigurations."alice@workstation" = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      stc.homeModules.cogitator-enginseer
      ./home.nix
    ];
  };
};

# home.nix
{
  stc.cogitator.enginseer.enable = true;

  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "24.11";
}
```

:::note[catppuccin module]
The Enginseer profile uses the `catppuccin` Home Manager module. This module
must be available in your module list. It is provided via STC's flake inputs —
import it as `stc.inputs.catppuccin.homeManagerModules.catppuccin` if you do not
have it in your own inputs.
:::
