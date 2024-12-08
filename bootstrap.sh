#!/bin/sh

BASEDIR="${0%/*}"

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
	cp "$BASEDIR/chroot-hack" "$CHROOT_HACK_PATH/chroot"

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
)

ret="$?"
[ "$ret" = 0 ] || echo "Build failed!" >&2
exit "$ret"
