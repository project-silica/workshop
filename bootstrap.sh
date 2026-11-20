#!/usr/bin/env bash
# Bring a fresh workshop clone to a runnable state: clone each pinned M0
# repository into the workshop at its pinned commit, check any that already
# exist, then let tools/sync.sh do the rest.
# Reads public repositories only; needs no credentials.
set -euo pipefail
cd "$(dirname "$0")"
root=$(pwd -P)
org=https://github.com/project-silica
pins=bootstrap.pins
die() { echo "ERROR: bootstrap: $*"; exit 1; }

pin_of() { # 40-hex commit pinned for $1, or empty
  [ -f "$pins" ] || return 0
  awk -v r="$1" '$1 == r { print $2 }' "$pins" | grep -E '^[0-9a-f]{40}$' || true
}

for repo in idl kernel os .github; do
  pin=$(pin_of "$repo")
  if [ -e "$repo" ]; then
    top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)
    [ "$top" = "$root/$repo" ] || die "$repo exists but is not its own Git repository"
    if [ -n "$pin" ]; then
      git -C "$repo" merge-base --is-ancestor "$pin" HEAD 2>/dev/null ||
        die "$repo HEAD does not contain pinned commit $pin"
    fi
    continue
  fi
  if [ -z "$pin" ]; then
    echo "SKIP: bootstrap: $repo is not pinned in $pins"
    continue
  fi
  git clone --quiet --no-checkout "$org/$repo.git" "$repo" || die "cannot clone $repo"
  git -C "$repo" cat-file -e "$pin^{commit}" 2>/dev/null || { rm -rf "$repo"; die "$repo has no commit $pin"; }
  git -C "$repo" checkout --quiet -B main "$pin" || die "cannot check out $repo at $pin"
done

[ ! -x tools/sync.sh ] || ./tools/sync.sh
[ -f spec/ARCHITECTURE.md ] || die "spec/ARCHITECTURE.md missing; this is not a complete workshop checkout"
echo "BOOTSTRAP: OK"
