#!/bin/bash

. allinone/utils

seconds="$1"

[ -z "$seconds" ] && read -r seconds

[ -n "$seconds" ] || die "Pass seconds to convert as one and only arg, or on stdin"

result="$(secs_to_duration "$seconds")"

echo "$result"
