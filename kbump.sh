#!/bin/sh
# kbump.sh -- bump a package version in place (version + sources + checksums).
#
# usage: kbump.sh [-c] <pkg> <old> <new> [sed-script-applied-to-sources]
#
#   -c   run "kiss checksum <pkg>" afterwards (the correct spelling; it
#        rewrites <dir>/checksums from the freshly fetched tarballs)
#
# The old version string is replaced by the new one in version and sources
# only.  Upstream build files are NEVER copied wholesale: this distro is
# libressl based, so ffmpeg needs the tls_libtls fix, libevent needs
# libresslfix.patch and php/ruby use local build scripts (see NOTES).
# Anything else (tarball renamed, path component bumped, patch added) is a
# hand edit after this script shows you the diff.
#
# Commit with kcommit.sh.  KISS revision (trailing "1") is untouched.
set -eu

REPO=${REPO:-/root/kiss/repo-main}
CATS=${CATS:-core extra community games xorg}
cd "$REPO"

doit=
if [ ${1:-} = -c ]; then doit=1; shift; fi
[ $# -ge 3 ] || { echo "usage: $0 [-c] <pkg> <old> <new> [sed-for-sources]" >&2; exit 2; }
pkg=$1; old=$2; new=$3; extra=${4:-}

dir=
for c in $CATS; do
  if [ -f "$c/$pkg/version" ]; then dir="$c/$pkg"; break; fi
done
[ -n "$dir" ] || { echo "no such package: $pkg" >&2; exit 1; }

cur=$(sed -n 1p "$dir/version" | cut -d" " -f1)
[ "$cur" = "$old" ] || { echo "SKIP $pkg: version is $cur, expected $old"; exit 1; }
grep -q -- "$old" "$dir/sources" || { echo "SKIP $pkg: $old not in sources"; exit 1; }

sed -i "s|$old|$new|g" "$dir/version" "$dir/sources"
[ -n "$extra" ] && sed -i "$extra" "$dir/sources" || :
[ -n "$doit" ] && kiss checksum "$pkg" || :

echo "### $pkg $old -> $new"
git -c core.pager=cat diff -- "$dir"
