#!/usr/bin/env bash
# Fail when STC writes an option priority that nothing accounts for.
#
# Why this seal exists, in one case: v0.18.0 demoted
# services.openssh.settings.X11Forwarding to lib.mkDefault. nixpkgs' slurm
# module writes the same setting as `mkIf cfg.client.enable (mkDefault true)`,
# so two mkDefaults disagreed and a hardened Slurm client — which built on the
# previous release — stopped evaluating. Nothing caught it: the rule was written
# down and still missed, because no command measured it. This is that command.
#
# It enforces two things:
#
#   1. Completeness. Every file under relics/ and cogitator/ that writes a
#      priority (lib.mkDefault / lib.mkForce / lib.mkOverride) has a row in the
#      register with the exact count and a reason. Add one without registering
#      it and this fails — which is the point: a priority is a decision, and an
#      unregistered decision is one taken in secret.
#
#   2. No silent collision. For every third-party option the register says STC
#      writes with mkDefault, the locked nixpkgs and home-manager are searched
#      for a module writing the same option, also with mkDefault. Two mkDefaults
#      that disagree are a build error at the consumer, so each hit must be
#      allow-listed with the reason it is harmless.
#
# What it deliberately does NOT do: infer option paths from the source. Tried and
# rejected — a nested block yields a bare leaf (`enable`, `mouse`) that names
# nothing greppable, and a brace leaks into the attribute name. The register
# carries the full path by hand, because that is the one thing a grep cannot
# supply; the counts above are what stop the register from drifting.
set -euo pipefail

register="scripts/option-priorities.tsv"
targets=(relics cogitator)

[ -f "$register" ] || {
  echo "error: $register not found (run from the repository root)" >&2
  exit 1
}

# Count priority calls in code only. Comments are stripped first: several module
# comments discuss mkForce in prose, and counting those would make the register
# a transcription of the documentation.
count_in() {
  sed 's/#.*$//' "$1" | grep -cE "lib\.$2 " || true
}

fail=0
note() {
  echo "error: $*" >&2
  fail=1
}

# ---------------------------------------------------------------------------
# 1. Completeness
# ---------------------------------------------------------------------------
live="$(mktemp)"
trap 'rm -f "$live"' EXIT

while IFS= read -r f; do
  d=$(count_in "$f" mkDefault)
  o=$(count_in "$f" mkForce)
  v=$(count_in "$f" mkOverride)
  [ $((d + o + v)) -eq 0 ] && continue
  printf '%s\t%s\t%s\t%s\n' "$f" "$d" "$o" "$v" >> "$live"
done < <(grep -rlE "lib\.mk(Default|Force|Override) " "${targets[@]}" --include="*.nix" | sort)

while IFS=$'\t' read -r file d o v; do
  row="$(awk -F'\t' -v f="$file" '$1 == "count" && $2 == f {print; exit}' "$register")"
  if [ -z "$row" ]; then
    note "$file writes a priority but has no row in $register
       add:  count<TAB>$file<TAB>$d<TAB>$o<TAB>$v<TAB><why these priorities are right>"
    continue
  fi
  rd=$(printf '%s' "$row" | cut -f3)
  ro=$(printf '%s' "$row" | cut -f4)
  rv=$(printf '%s' "$row" | cut -f5)
  reason=$(printf '%s' "$row" | cut -f6)
  [ "$d" = "$rd" ] && [ "$o" = "$ro" ] && [ "$v" = "$rv" ] ||
    note "$file: register says mkDefault=$rd mkForce=$ro mkOverride=$rv, found $d/$o/$v
       a priority was added or removed without a ruling — update $register"
  [ -n "$reason" ] || note "$file: register row carries no reason"
done < "$live"

# Stale rows: a file that no longer writes a priority, or no longer exists.
while IFS=$'\t' read -r _ file _ _ _ _; do
  [ -n "$file" ] || continue
  cut -f1 "$live" | grep -qxF "$file" ||
    note "$register lists $file, which writes no priority any more — drop the row"
done < <(awk -F'\t' '$1 == "count"' "$register")

# ---------------------------------------------------------------------------
# 2. No silent collision with an upstream default
# ---------------------------------------------------------------------------
nixpkgs="$(nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')"
hm="$(nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.home-manager.outPath')"

upstream_dirs=()
[ -d "$nixpkgs/nixos/modules" ] && upstream_dirs+=("$nixpkgs/nixos/modules")
[ -d "$hm/modules" ] && upstream_dirs+=("$hm/modules")
[ ${#upstream_dirs[@]} -gt 0 ] || note "could not resolve the locked nixpkgs/home-manager module trees"

while IFS=$'\t' read -r _ path owner _; do
  [ -n "$path" ] || continue
  # Two patterns, and neither is the bare leaf. Matching the last component
  # alone was the first draft and it was useless: `command`, `package` and
  # `enable` hit half of nixpkgs. So: the full dotted path, which is how
  # upstream usually writes an option, plus its last two components, which is
  # how a module writing inside a nested block spells it. A module that writes
  # only the bare leaf inside a block can still escape this — recorded as the
  # seal's known blind spot rather than papered over.
  clean="${path//\"/}"
  patterns=("$clean")
  case "$clean" in
    *.*.*)
      tail_two="${clean#"${clean%.*.*}".}"
      patterns+=("$tail_two")
      ;;
  esac

  hits=""
  for pat in "${patterns[@]}"; do
    # A preceding dot must match too: a pattern that excluded it is exactly how
    # an earlier draft missed the slurm collision this seal was written for.
    found="$(grep -rhE "[.[:space:]]${pat}[[:space:]]*=" "${upstream_dirs[@]}" 2>/dev/null |
      grep "mkDefault" || true)"
    [ -n "$found" ] && hits="${hits}${found}
"
  done
  hits="$(printf '%s' "$hits" | grep -v '^$' || true)"
  [ -n "$hits" ] || continue

  if awk -F'\t' -v p="$path" '$1 == "allow" && $2 == p {found = 1} END {exit !found}' "$register"; then
    continue
  fi
  note "$path (written with mkDefault by $owner) has a competing upstream mkDefault:
$(printf '%s\n' "$hits" | sed 's/^[[:space:]]*/       /' | head -3)
       two disagreeing mkDefaults are a build error at the consumer. Either write
       the value from an STC option at normal priority, or add:
       allow<TAB>$path<TAB><upstream module><TAB><why the collision is harmless>"
done < <(awk -F'\t' '$1 == "watch"' "$register")

if [ "$fail" -ne 0 ]; then
  echo >&2
  echo "option priorities: FAILED — see $register and" >&2
  echo "       docs/src/content/docs/en/reference/overridable-defaults.md" >&2
  exit 1
fi

printf 'option priorities OK: %s files registered, %s third-party options watched.\n' \
  "$(awk -F'\t' '$1 == "count"' "$register" | wc -l)" \
  "$(awk -F'\t' '$1 == "watch"' "$register" | wc -l)"
