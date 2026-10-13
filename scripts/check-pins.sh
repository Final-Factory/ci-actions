#!/usr/bin/env bash
# check-pins.sh -- every remote `uses:` in an action.yml or workflow is pinned by full commit id.
#
# Why: the FFBox host's action cache (ffbox scripts/actioncache.py) fetches only commit ids, and only
# from owners on its action_cache_owners (default: actions, Final-Factory). A tag would miss that
# cache the moment it moved and fail every FFBox job at "Set up job"; an owner not on the list is
# refused by the host. This keeps both mistakes out of main.
set -euo pipefail
cd "$(dirname "$0")/.."
owners=${ALLOWED_OWNERS:-"actions Final-Factory"}
bad=0
while IFS= read -r line; do
  file=${line%%:*}; rest=${line#*:}; rest=${rest#*:}
  ref=$(sed -E 's/.*uses:[[:space:]]*["'"'"']?([^"'"'"'[:space:]#]+).*/\1/' <<<"$rest")
  case "$ref" in ./*|docker://*) continue ;; esac
  owner=${ref%%/*}; at=${ref##*@}
  if ! [[ "$at" =~ ^[0-9a-f]{40}$ ]]; then echo "$file: $ref is not pinned by a full commit id"; bad=1; fi
  if ! [[ " $owners " == *" $owner "* ]]; then echo "$file: $ref: owner $owner is not on the FFBox host's action_cache_owners ($owners)"; bad=1; fi
done < <(grep -rnE '^\s*(-\s*)?uses:' --include=action.yml --include='*.yml' . | grep -v '^./.git/')
[ "$bad" = 0 ] && echo "every uses: is pinned by commit, from an allowed owner"
exit "$bad"
