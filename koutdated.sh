#!/bin/sh
# koutdated.sh -- find outdated packages WITHOUT repology.
#
# Source of truth is the set of git remotes configured in this repo:
#   repo     kiss-community/repo       codeberg  core + extra
#   com      kiss-community/community  codeberg  community
#   xorg     echawk/kiss-xorg          github
#   personal echawk/kiss-personal      github
#   oakiss   hovercats/oakiss          github    (advisory, own versioning)
#
# repology.org is unreachable (curl 7, connection refused), so the
# repology-backed "kiss outdated" is useless here.  Method: export every
# remote tracking ref with git archive, then diff version files against
# the working tree with sort -V.  Runs offline once the fetch succeeded.
#
# usage:
#   koutdated.sh fetch   gru + git archive each ref -> $WORK/rem/<ref>
#   koutdated.sh scan    -> $WORK/remote.vers and $WORK/local.vers
#   koutdated.sh diff    -> $WORK/outdated.txt, advisory.txt and ./.dated
#   koutdated.sh all     fetch + scan + diff (default)
#
# Output columns (tab separated):
#   remote.vers   name  version  ref/category/pkg/version
#   local.vers    name  version  category
#   outdated.txt  name  local  remote  ref  category     (real candidates)
#   advisory.txt  name  local  remote  ref               (cosmetic only)
#
# Cosmetic differences are NOT bumps: oakiss prefixes versions with v
# (v1.10.0 == 1.10.0), appends distro suffixes (6.0-29) or git describe
# strings (1.3-11-gaddea50762).  Those land in advisory.txt.
# See NOTES for packages deliberately kept behind upstream.

set -eu

REPO=${REPO:-/root/kiss/repo-main}
WORK=${WORK:-/tmp/kout}
CATS=${CATS:-core extra community games xorg}
# refs whose version style differs (oakiss uses pkg/<name>/ver and its own
# tagging); treat as advisory instead of bump candidates.
ADVISORY=${ADVISORY:-oakiss}
export LC_ALL=C

fetch() {
  (command -v gru >/dev/null 2>&1 && gru) || git remote update --prune
  mkdir -p "$WORK/rem"
  git for-each-ref --format="%(refname:lstrip=2)" refs/remotes > "$WORK/refs.raw"
  while read ref; do
    [ -n "$ref" ] || continue
    flat=$(printf %s "$ref" | tr / _)
    rm -rf "$WORK/rem/$flat"
    mkdir -p "$WORK/rem/$flat"
    if git archive "$ref" 2>/dev/null | tar -x -C "$WORK/rem/$flat"; then
      echo "archived $ref -> $WORK/rem/$flat"
    fi
  done < "$WORK/refs.raw"
}

remotepaths() {
  for d in "$WORK"/rem/*/; do
    [ -d "$d" ] || continue
    find "$d" -type f \( -name version -o -path "*/pkg/*/ver" \) 2>/dev/null
  done
}

scan() {
  remotepaths | sort -u > "$WORK/vfiles"
  while read f; do
    rel=${f#"$WORK/rem/"}
    name=$(basename "$(dirname "$f")")
    ver=$(sed -n 1p "$f" | cut -d " " -f1)
    [ -n "$ver" ] || continue
    printf "%s	%s	%s
" "$name" "$ver" "$rel"
  done < "$WORK/vfiles" | sort > "$WORK/remote.vers"

  : > "$WORK/local.vers"
  for c in $CATS; do
    [ -d "$c" ] || continue
    find "$c" -mindepth 2 -maxdepth 2 -type f -name version | while read f; do
      printf "%s	%s	%s
" "$(echo "$f" | cut -d / -f 2)" \
        "$(sed -n 1p "$f" | cut -d " " -f1)" "$c"
    done >> "$WORK/local.vers"
  done
  sort -o "$WORK/local.vers" "$WORK/local.vers"
  echo "remote.vers $(wc -l < "$WORK/remote.vers") local.vers $(wc -l < "$WORK/local.vers")"
}

AWK=${AWK:-$(dirname "$(readlink -f "$0")")/koutdated.awk}

diff() {
  awk -v advisory="$ADVISORY" -f "$AWK" "$WORK/remote.vers" "$WORK/local.vers" > "$WORK/classified.txt"

  awk -F"	" "\$1==\"C\"{printf \"%-26s local=%-20s remote=%-20s %s (%s)\\n\",\$2,\$3,\$4,\$5,\$6}" "$WORK/classified.txt" > "$WORK/outdated.txt"
  awk -F"	" "\$1==\"A\"{printf \"%-26s local=%-20s remote=%-20s %-22s %s\\n\",\$2,\$3,\$4,\$5,\$6}" "$WORK/classified.txt" > "$WORK/advisory.txt"
  awk -F"	" "\$1==\"S\"{printf \"%-26s %s\\n\",\$2,\$3}" "$WORK/classified.txt" > "$WORK/onlylocal.txt"
  awk -F"	" "\$1==\"C\"{printf \"%s\\t%s -> %s\\n\",\$2,\$3,\$4}" "$WORK/classified.txt" > "$WORK/refs.txt"

  cp "$WORK/refs.txt" .dated
  printf "candidates %s  advisory %s  only-in-repo %s  (WORK=$WORK, .dated written)
" \
    "$(wc -l < "$WORK/outdated.txt")" "$(wc -l < "$WORK/advisory.txt")" "$(wc -l < "$WORK/onlylocal.txt")"
}

case ${1:-all} in
  fetch) fetch ;;
  scan)  scan ;;
  diff)  diff ;;
  all)   fetch; scan; diff ;;
  *)     echo "usage: $0 [fetch|scan|diff|all]" >&2 ; exit 2 ;;
esac
