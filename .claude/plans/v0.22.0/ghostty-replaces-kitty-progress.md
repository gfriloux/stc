# Ledger — plan: .claude/plans/v0.22.0/ghostty-replaces-kitty.md

Pre-flight: issue #1 read; consumer `gfriloux/nixos` grepped (cogitator-desktop
imported, no kitty option set).

Step 1: Ruling: the user's third answer ("Oui" to "full lot or light
variant?") read as the full lot, #1 + #40 + #31 + #33.

Step 1: Ruling: options typed `nullOr bool` so that an explicit `false` warns
too — it is the line the old docs taught to drop kitty from the profile.
Step 2: Ruling: scripts/option-priorities.tsv desktop row goes 3/0/1 → 2/0/1 (kitty's mkDefault removed); the seal caught it, as designed.

Step 2: `relics/home/ghostty.nix` gains `fonts.enable` (7 packages);
`relics/home/kitty.nix` is a tombstone (options `nullOr bool`, `visible =
false`, `warnings` only); `cogitator/home/desktop.nix` drops `kitty.enable`.
Measured by `nix-instantiate --eval` on a homeManagerConfiguration with the
cogitator: no definition → 0 warnings; `kitty.enable = true` → 1;
`kitty.enable = false` → 1; `kitty.fonts.enable = false` → 1; alias
`stc.gui.kitty.enable` → 2 (rename + removal); `programs.kitty.enable` stays
false with `kitty.enable = true`; fonts 7 packages, 0 with
`ghostty.fonts.enable = false`.

Step 3: `provings/home-desktop.nix`: kitty subtests replaced by "kitty is gone
from the profile" (no `~/.config/kitty`, no `bin/kitty`), fonts subtest now
attributed to ghostty, composed node checks the ghostty unit. Green first run.

Step 4: docs EN + FR — home-apps (Kitty section → "removed" section at the
end), cogitator/desktop ("Keeping one terminal" → "Kitty removed in
v0.22.0"), relics/index, cogitator/index, overridable-defaults,
getting-started, architecture, provings/index.

Gates: `just ci` green; proving `home-desktop` green; local-vm and aws-ami
drvPath evaluate; consumer `gfriloux/nixos` `kuri@exampleHost`
activationPackage evaluates with `--override-input`, no kitty warning.

Deferred minor: `provings/index.md` (EN+FR) still says desktop wins with
`mkForce pinentry-qt`; it is `mkOverride 900` since #86. Pre-existing, not #1.
