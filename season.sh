#!/bin/bash -e

[ $# -eq 1 ] || {
	echo "Pass the name of a file to determine what season of a TV series it is."
	exit 1
}

RE=".* s([[:digit:]]+)e.*"
[[ "$1" =~ $RE ]] && {
	printf "%d\n" "${BASH_REMATCH[1]}"
} || {
	echo "Couldn't determine season from file name." >&2
	exit 1
}
