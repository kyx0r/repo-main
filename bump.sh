#!/bin/sh -e

bump() {
	../bump.sh "$1"
	gal && kcmv
}

[ -z "$1" ] && exit 0
EXINIT="g/$1/;;>[ 	]>ya1\:;>[0-9.]+ -\>>;#> >mas\:;'a;'sya2\:;'s;#+1;#>[0-9]>;#>[^0-9.]|\$>ya3:??!p Failed to find $1\:q\!:reg:cd ./%@1:e version:%s/%@2/%@3/g:??w:e sources:%s/%@2/%@3/g:??w\:\!kiss checksum:q" vi -vem .dated
