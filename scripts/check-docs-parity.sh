#!/usr/bin/env bash
# Fail if the English and French documentation trees diverge.
#
# The docs are bilingual and mirrored by hand: every page under en/ must have a
# counterpart at the same relative path under fr/, and vice versa. This catches
# the most common rot — a page added or renamed in one language but not the other.
# It compares the set of relative file paths, not their content.
set -euo pipefail

base="docs/src/content/docs"

if [ ! -d "$base/en" ] || [ ! -d "$base/fr" ]; then
  echo "error: expected $base/en and $base/fr to exist" >&2
  exit 1
fi

en="$(cd "$base/en" && find . -type f | sort)"
fr="$(cd "$base/fr" && find . -type f | sort)"

if ! diff <(printf '%s\n' "$en") <(printf '%s\n' "$fr"); then
  echo >&2
  echo "error: en/ and fr/ documentation trees are out of sync (see diff above)." >&2
  echo "       '<' lines exist only in en/, '>' lines only in fr/." >&2
  exit 1
fi

echo "docs parity OK: en/ and fr/ trees match."
