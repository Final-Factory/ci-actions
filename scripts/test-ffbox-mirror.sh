#!/usr/bin/env bash
# test-ffbox-mirror.sh -- ffbox-mirror.sh against a fake FFBox host. Offline.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else fail=$((fail + 1)); echo "  FAIL $1: got [$2], want [$3]"; fi; }

# The fake host has exactly the commits listed in $tmp/have, and logs every request.
cat > "$tmp/ws" <<'FAKE'
#!/usr/bin/env bash
echo "$2" >> "$TMPD/asked"
grep -qx "$2" "$TMPD/have"
FAKE
chmod +x "$tmp/ws"
MERGE=1111111111111111111111111111111111111111
HEAD=2222222222222222222222222222222222222222

run() {   # env assignments... ; prints the script's exit status
  : > "$tmp/out"; : > "$tmp/asked"
  env TMPD="$tmp" FFGHR_WORKSPACE="$tmp/ws" GITHUB_OUTPUT="$tmp/out" "$@" "$here/ffbox-mirror.sh" > "$tmp/log" 2>&1
  echo $?
}
out() { sed -n "s/^$1=//p" "$tmp/out"; }

echo "not FFBox"
check "exits 0" "$(run FFGHR_GIT_MIRROR= SHA=$MERGE)" 0
check "says ffbox=false" "$(out ffbox)" false
check "asks the host nothing" "$(cat "$tmp/asked")" ""

echo "FFBox, the commit is there"
printf '%s\n' $MERGE $HEAD > "$tmp/have"
check "exits 0" "$(run FFGHR_GIT_MIRROR=git://m/x.git SHA=$MERGE EVENT=pull_request HEAD_SHA=$HEAD)" 0
check "says ffbox=true" "$(out ffbox)" true
check "no other ref" "$(out ref)" ""
check "asked once, for the merge" "$(cat "$tmp/asked")" "$MERGE"

echo "FFBox, a merged pull request (the test merge is gone)"
printf '%s\n' $HEAD > "$tmp/have"
check "exits 0" "$(run FFGHR_GIT_MIRROR=git://m/x.git SHA=$MERGE EVENT=pull_request HEAD_SHA=$HEAD)" 0
check "checks out the head" "$(out ref)" "$HEAD"
check "asked for the merge, then the head" "$(tr '\n' ' ' < "$tmp/asked")" "$MERGE $HEAD "
check "and warns" "$(grep -c '::warning::' "$tmp/log")" 1

echo "FFBox, no fallback"
check "a push whose commit is gone fails" "$(run FFGHR_GIT_MIRROR=git://m/x.git SHA=$MERGE EVENT=push)" 1
check "and asks only once" "$(cat "$tmp/asked")" "$MERGE"
check "a ref the caller asked for is not replaced" \
  "$(run FFGHR_GIT_MIRROR=git://m/x.git SHA=$MERGE EVENT=pull_request HEAD_SHA=$HEAD REF_IN=main)" 1
check "a head that is not a commit id is not used" \
  "$(run FFGHR_GIT_MIRROR=git://m/x.git SHA=$MERGE EVENT=pull_request HEAD_SHA='x;rm -rf /')" 1
: > "$tmp/have"
check "a head the host cannot fetch either fails" \
  "$(run FFGHR_GIT_MIRROR=git://m/x.git SHA=$MERGE EVENT=pull_request HEAD_SHA=$HEAD)" 1
check "with no ref written" "$(out ref)" ""

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
