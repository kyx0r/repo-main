#!/bin/sh
# Source on demand: . ./kiss-helpers.sh
# Functions: bootstrap, bump, bump_dated, download, kbump, kcommit, koutdated.

kiss_usage() {
	cat <<'EOF'
KISS repository shell helpers

Source on demand:   . ./kiss-helpers.sh
Then call:          bootstrap [output.tar]
                    bump pkg
                    bump_dated pkg
                    download
                    kbump [-c] pkg old new [sed-script]
                    kcommit pkg version [pkg version ...]
                    koutdated [fetch|scan|diff|all]
                    kiss_usage

Run from the repository root. bootstrap reads ./conf (or $KBOOTSTRAP_DIR/conf).
Set REPO, CATS, WORK, AWK, etc. before calling helpers to override defaults.
EOF
}

# $0 names this file when executed, but not when sourced from another script.
case "$0" in
*kiss-helpers.sh) kiss_usage >&2; exit 1 ;;
esac

# --- bootstrap ---
# KBOOTSTRAP_DIR defaults to the current directory (conf).
bootstrap() (
BASEDIR=${KBOOTSTRAP_DIR:-.}

. "$BASEDIR/conf"

set -eu

: "${KBOOTSTRAP_KISS_PATH:?}"
: "${KBOOTSTRAP_PACKAGES:?}"
: "${KBOOTSTRAP_CFLAGS:=-march=x86-64 -mtune=generic -pipe -Os}"
: "${KBOOTSTRAP_CXXFLAGS:=-march=x86-64 -mtune=generic -pipe -Os}"
: "${KBOOTSTRAP_MAKEFLAGS:=-j$(nproc)}"

OUTFILE="${1:-$PWD/kiss-chroot-$(date +'%y-%m-%d').tar}"
OUTFILE="$(realpath "$OUTFILE")"

TMPDIR=/tmp/kroot

STAGE="stage"
DUMMY_PACKAGE_DIR="$TMPDIR/repo/__dummy-bootstrap"
CHROOT_HACK_PATH="$TMPDIR/chroot_path"

rm -rf $DUMMY_PACKAGE_DIR

setenv() {
	export AR=ar
	export CC=cc
	export CXX=c++
	export NM=nm
	export RANLIB=ranlib
	export CFLAGS="$KBOOTSTRAP_CFLAGS"
	export CXXFLAGS="$KBOOTSTRAP_CXXFLAGS"
	export MAKEFLAGS="$KBOOTSTRAP_MAKEFLAGS"

	unset CPPFLAGS

	export KISS_ROOT="$1"
	export KISS_PATH="$KBOOTSTRAP_KISS_PATH"

	cac_dir=${XDG_CACHE_HOME:-"${HOME%"${HOME##*[!/]}"}/.cache"}
	cac_dir=${cac_dir%"${cac_dir##*[!/]}"}/kiss/sources

	mkdir -p "$cac_dir"

	# Don't use host binary cache, just sources
	XDG_CACHE_HOME="$TMPDIR/$(date +%s)"
	export XDG_CACHE_HOME

	mkdir -p "$XDG_CACHE_HOME/kiss"

	ln -sf "$cac_dir" "$XDG_CACHE_HOME/kiss/sources"
}

ret=0

cat <<EOF
KBOOTSTRAP_KISS_PATH = $KBOOTSTRAP_KISS_PATH
KBOOTSTRAP_PACKAGES = $KBOOTSTRAP_PACKAGES
KBOOTSTRAP_CFLAGS = $KBOOTSTRAP_CFLAGS
KBOOTSTRAP_CXXFLAGS = $KBOOTSTRAP_CXXFLAGS
KBOOTSTRAP_MAKEFLAGS = $KBOOTSTRAP_MAKEFLAGS
OUTFILE = $OUTFILE
EOF

set +e

(
	set -e

	echo "Ctrl + C to cancel building"
	read -r _

	mkdir -p "$TMPDIR/$STAGE"
	mkdir -p "$CHROOT_HACK_PATH"
	# Supply the chroot guard as an executable for kiss; no separate
	# shell script needs to be kept alongside this library.
	cat > "$CHROOT_HACK_PATH/chroot" <<'CHROOT_GUARD'
#!/bin/sh -e
cd -P "${1:?No path provided}"
[ "$PWD" = '/' ] || {
    printf '%s\n' "$PWD is not the real root!"
    exit 1
}
CHROOT_GUARD
	chmod +x "$CHROOT_HACK_PATH/chroot"

	kiss new "$DUMMY_PACKAGE_DIR" 1

	# shellcheck disable=2086
	set -- $KBOOTSTRAP_PACKAGES

	[ "$1" = "baselayout" ] || {
		echo "First package to build must be 'baselayout'!" >&2
		return 1
	}

	printf '%s\n' "$@" > "$DUMMY_PACKAGE_DIR/depends"

	# Initial build using host toolchain
	(
		setenv "$TMPDIR/$STAGE"
		# shellcheck disable=2030
		export LD_LIBRARY_PATH="$TMPDIR/$STAGE/lib"
		# shellcheck disable=2030
		export PATH="$TMPDIR/$STAGE/bin:$PATH"

		cd "$DUMMY_PACKAGE_DIR"
		LOGNAME=root KISS_PROMPT=0 kiss build
	)
	echo "successfully built STAGE"
	echo "Ctrl + C to cancel tarball"
	read -r _
	tar cf "$OUTFILE" . -C "$TMPDIR/$STAGE"
	echo "Ctrl + C to cancel tarball compression"
	read -r _
	xz -z -c -9 "$OUTFILE" > "${OUTFILE}.xz"
)

ret="$?"
[ "$ret" = 0 ] || echo "Build failed!" >&2
return "$ret"

)

# --- bump ---
bump() {
	bump_dated "$1"
	gal && kcmv
}

bump_dated() {
	[ -n "${1:-}" ] || return 0
	EXINIT="g/$1/;;>[ 	]>ya1\:;>[0-9.]+ -\>>;#> >m97 115\:;'97;'115ya2\:;'115;#+1;#>[0-9]>;#>[^0-9.]|\$>ya3:??!p Failed to find $1\:q\!:reg:cd ./%@1:e version:%s/%@2/%@3/g:??w:e sources:%s/%@2/%@3/g:??w\:\!kiss checksum:q" vi -vem .dated
}

# --- download ---
download() (
: "${KISS_PATH:=/var/db/kiss/installed}"
IFS=:
unset c1
unset c2
unset c3
for repo in $KISS_PATH; do
    [ -d "$repo" ] || continue
    for pkg in "$repo"/*/; do
        pkg=${pkg%*/}  # remove trailing slash
        [ -d "$pkg" ] || continue  # ensures it's a dir (and glob matched)
        ret="$(kiss download "${pkg##*/}" 2>&1 1>/dev/null)"
        printf '%s\n' "$ret" | {
            while IFS= read -r line; do
                # Skip only the specific error about missing version file
                case $line in
                    *'Failed to read version file ('*'/version)' )
                        # Ignore this line
                        ;;
                    *'ERROR'* )
                        printf '%s\n' "$line" >&2
                        touch err
                        ;;
                    *)
                        # Pass through all other output
                        printf '%s\n' "$line" >&2
                        ;;
                esac
            done
        }
        if [ -f err ]; then
        	rm err
        	exit 1
        fi
    done
done | sort -u

)

# --- kbump ---
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
kbump() (
  set -eu

  REPO=${REPO:-/root/kiss/repo-main}
  CATS=${CATS:-core extra community games xorg}
  cd "$REPO"

  doit=
  if [ ${1:-} = -c ]; then doit=1; shift; fi
  [ $# -ge 3 ] || { echo "usage: kbump [-c] <pkg> <old> <new> [sed-for-sources]" >&2; return 2; }
  pkg=$1; old=$2; new=$3; extra=${4:-}

  dir=
  for c in $CATS; do
    if [ -f "$c/$pkg/version" ]; then dir="$c/$pkg"; break; fi
  done
  [ -n "$dir" ] || { echo "no such package: $pkg" >&2; return 1; }

  cur=$(sed -n 1p "$dir/version" | cut -d" " -f1)
  [ "$cur" = "$old" ] || { echo "SKIP $pkg: version is $cur, expected $old"; return 1; }
  grep -q -- "$old" "$dir/sources" || { echo "SKIP $pkg: $old not in sources"; return 1; }

  sed -i "s|$old|$new|g" "$dir/version" "$dir/sources"
  [ -n "$extra" ] && sed -i "$extra" "$dir/sources" || :
  [ -n "$doit" ] && kiss checksum "$pkg" || :

  echo "### $pkg $old -> $new"
  git -c core.pager=cat diff -- "$dir"

)

# --- kcommit ---
# kcommit.sh -- commit one commit per bumped package (kiss style message).
#
# usage: kcommit.sh <pkg> <version> [<pkg> <version> ...]
# e.g.   kcommit.sh gzip 1.15 socat 1.8.1.3
#
# Message format matches the repo history: "pkg: <version> 1"
kcommit() (
  set -eu

  REPO=${REPO:-/root/kiss/repo-main}
  CATS=${CATS:-core extra community games xorg}
  cd "$REPO"

  [ $# -ge 2 ] || { echo "usage: kcommit <pkg> <version> [<pkg> <version> ...]" >&2; return 2; }
  [ $# -eq $(( $# / 2 * 2 )) ] || { echo "give pkg AND version for every entry" >&2; return 2; }

  while [ $# -gt 0 ]; do
    pkg=$1; ver=$2; shift 2
    dir=
    for c in $CATS; do
      if [ -f "$c/$pkg/version" ]; then dir="$c/$pkg"; break; fi
    done
    [ -n "$dir" ] || { echo "no such package: $pkg" >&2; return 1; }
    if git diff --quiet -- "$dir"; then
      echo "nothing to commit for $pkg"
      continue
    fi
    git add "$dir"
    git commit -q -m "$pkg: $ver 1"
    echo "committed $pkg: $ver 1  ($(git log --oneline -1 -- "$dir"))"
  done

)

# --- koutdated ---
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

koutdated() (
set -eu

REPO=${REPO:-/root/kiss/repo-main}
WORK=${WORK:-/tmp/kout}
CATS=${CATS:-core extra community games xorg}
# refs whose version style differs (oakiss uses pkg/<name>/ver and its own
# tagging); treat as advisory instead of bump candidates.
ADVISORY=${ADVISORY:-oakiss}
export LC_ALL=C

koutdated_fetch() {
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

koutdated_remotepaths() {
  for d in "$WORK"/rem/*/; do
    [ -d "$d" ] || continue
    find "$d" -type f \( -name version -o -path "*/pkg/*/ver" \) 2>/dev/null
  done
}

koutdated_scan() {
  koutdated_remotepaths | sort -u > "$WORK/vfiles"
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

AWK=${AWK:-$REPO/koutdated.awk}

koutdated_diff() {
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
  fetch) koutdated_fetch ;;
  scan)  koutdated_scan ;;
  diff)  koutdated_diff ;;
  all)   koutdated_fetch; koutdated_scan; koutdated_diff ;;
  *)     echo "usage: koutdated [fetch|scan|diff|all]" >&2 ; return 2 ;;
esac

)
