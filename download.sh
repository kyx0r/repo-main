#!/bin/sh

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
