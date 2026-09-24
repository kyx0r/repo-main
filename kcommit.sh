#!/bin/sh
# kcommit.sh -- commit one commit per bumped package (kiss style message).
#
# usage: kcommit.sh <pkg> <version> [<pkg> <version> ...]
# e.g.   kcommit.sh gzip 1.15 socat 1.8.1.3
#
# Message format matches the repo history: "pkg: <version> 1"
set -eu

REPO=${REPO:-/root/kiss/repo-main}
CATS=${CATS:-core extra community games xorg}
cd "$REPO"

[ $# -ge 2 ] || { echo "usage: $0 <pkg> <version> [<pkg> <version> ...]" >&2; exit 2; }
[ $# -eq $(( $# / 2 * 2 )) ] || { echo "give pkg AND version for every entry" >&2; exit 2; }

while [ $# -gt 0 ]; do
  pkg=$1; ver=$2; shift 2
  dir=
  for c in $CATS; do
    if [ -f "$c/$pkg/version" ]; then dir="$c/$pkg"; break; fi
  done
  [ -n "$dir" ] || { echo "no such package: $pkg" >&2; exit 1; }
  if git diff --quiet -- "$dir"; then
    echo "nothing to commit for $pkg"
    continue
  fi
  git add "$dir"
  git commit -q -m "$pkg: $ver 1"
  echo "committed $pkg: $ver 1  ($(git log --oneline -1 -- "$dir"))"
done
