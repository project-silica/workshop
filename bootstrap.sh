#!/usr/bin/env bash
# Bring a fresh workshop clone to a runnable state: clone each pinned M0
# repository next to the harness at its pinned commit, check any that already
# exist, then let tools/sync.sh do the rest.
# Reads public repositories only; needs no credentials.
set -euo pipefail
cd "$(dirname "$0")"
root=$(pwd -P)
org=https://github.com/project-silica
pins=bootstrap.pins
g() { git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }
die() { echo "ERROR: bootstrap: $*"; exit 1; }

pin_of() { # 40-hex commit pinned for $1, or empty
  [ -f "$pins" ] || return 0
  awk -v r="$1" '$1 == r { print $2 }' "$pins" | grep -E '^[0-9a-f]{40}$' || true
}

trusted_os=0
for repo in spec idl kernel os .github; do
  pin=$(pin_of "$repo")
  if [ -e "$repo" ]; then
    top=$(g -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)
    [ "$top" = "$root/$repo" ] || die "$repo exists but is not its own Git repository"
    url=$(g -C "$repo" remote get-url origin 2>/dev/null || true)
    case "$url" in ""|"$org/$repo"|"$org/$repo.git") ;; *) die "$repo has unexpected origin $url" ;; esac
    if [ -n "$pin" ]; then
      g -C "$repo" merge-base --is-ancestor "$pin" HEAD 2>/dev/null ||
        die "$repo HEAD does not contain pinned commit $pin"
    fi
    [ "$repo" = os ] && trusted_os=1
    continue
  fi
  if [ -z "$pin" ]; then
    echo "SKIP: bootstrap: $repo is not pinned in $pins"
    continue
  fi
  g clone --quiet --no-checkout "$org/$repo.git" "$repo" || die "cannot clone $repo"
  g -C "$repo" cat-file -e "$pin^{commit}" 2>/dev/null || { rm -rf "$repo"; die "$repo has no commit $pin"; }
  g -C "$repo" checkout --quiet -B main "$pin" || die "cannot check out $repo at $pin"
  [ "$repo" = os ] && trusted_os=1
done

# Run os code only from an os checkout that passed the checks above.
if [ "$trusted_os" = 1 ] && [ -x tools/sync.sh ]; then
  ./tools/sync.sh
fi
[ -f spec/ARCHITECTURE.md ] || die "spec/ARCHITECTURE.md missing; publish and pin the spec repository first"
echo "BOOTSTRAP: OK"
