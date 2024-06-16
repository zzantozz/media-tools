#!/bin/bash

. allinone/utils

while getopts ":t:r:d:" opt; do
  case "$opt" in
    t)
      title_slug="$OPTARG"
      ;;
    r)
      release_slug="$OPTARG"
      ;;
    d)
      disk_index="$OPTARG"
      ;;
    *)
      die "Unrecognized arg: $OPTARG"
      ;;
  esac
done

[ -n "$title_slug" ] || die "Set a title slug with -t"
[ -n "$release_slug" ] || die "Set a release slug with -r"
[ -n "$disk_index" ] || die "Set a disk index with -d"
[[ "$disk_index" =~ ^[0-9]+$ ]] || die "Disk index must be numeric"

read -rd '' query <<EOF
query {
  mediaItems(where: {slug: {eq: \"$title_slug\"}}) {
    nodes {
      title
      fullTitle
      releases(where: {slug: {eq: \"$release_slug\"}}) {
        title
        discs(where: {index: {eq: $disk_index}}) {
          format
          index
          name
          slug
          titles(where: {item: {and: {title: {neq: null}}}}) {
            id
            duration
            segmentMap
            size
            sourceFile
            item {
              description
              episode
              id
              season
              title
              type
            }
          }
        }
      }
    }
    pageInfo {
      endCursor
      hasNextPage
      hasPreviousPage
      startCursor
    }
  }
}
EOF

#echo "query will be: " $query
flat_query="$(echo "$query" | tr -d '\n')"
#echo "flat query=$flat_query"

curl -s https://thediscdb.com/graphql -H 'content-type: application/json' -d "{\"query\": \"$flat_query\"}"
