#!/bin/sh
gcop() {
	first="$1"; shift;
	for var in "$@"
	do
		git checkout "$first" -- "$var"
	done
}

gcop repo core
git reset
rm -rf core/openssl
rm -rf core/curl/files
rm -rf core/certs
