#!/bin/sh -e

: "${KISS_PATH:=/var/db/kiss/installed}"
IFS=:
for repo in $KISS_PATH; do
    [ -d "$repo" ] || continue
    for pkg in "$repo"/*/; do
        pkg=${pkg%*/}  # remove trailing slash
        [ -d "$pkg" ] || continue  # ensures it's a dir (and glob matched)
        #printf '%s\n' "${pkg##*/}"  # print basename
        kiss download "${pkg##*/}"
    done
done | sort -u
