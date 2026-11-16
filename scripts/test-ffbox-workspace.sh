#!/usr/bin/env bash
# test-ffbox-workspace.sh -- ffbox-workspace.sh against a fake FFBox image script. Offline.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"; else fail=$((fail + 1)); echo "  FAIL $1: got [$2], want [$3]"; fi; }

# The fake image script: branch-key turns / into _2f (enough of the real key for these cases); restore
# and save log their arguments, one per line, after the verb.
cat > "$tmp/ws" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  branch-key) printf '%s\n' "${2//\//_2f}" ;;
  restore|save) shift; printf '%s\n' "$@" > "$TMPD/args.$VERBSEEN"; ;;
  *) exit 2 ;;
esac
FAKE
chmod +x "$tmp/ws"

run() {   # env assignments... ; prints the script's exit status
  : > "$tmp/out"; rm -f "$tmp"/args.*
  env TMPD="$tmp" VERBSEEN=x FFGHR_WORKSPACE="$tmp/ws" GITHUB_OUTPUT="$tmp/out" "$@" "$here/ffbox-workspace.sh" > "$tmp/log" 2>&1
  echo $?
}
out() { sed -n "s/^$1=//p" "$tmp/out"; }
args() { tr '\n' ' ' 2>/dev/null < "$tmp/args.x" | sed 's/ $//'; }

echo "caller mistakes"
check "an unknown verb fails" "$(run VERB=keep SCOPE=s FFGHR_GIT_MIRROR=git://m/x.git)" 2
check "no scope fails" "$(run VERB=restore FFGHR_GIT_MIRROR=git://m/x.git)" 2

echo "not FFBox"
check "exits 0" "$(run VERB=restore SCOPE=s FFGHR_GIT_MIRROR= REF_NAME=main)" 0
check "says ffbox=false" "$(out ffbox)" false
check "runs nothing" "$(args)" ""

echo "restore, a push"
check "exits 0" "$(run VERB=restore SCOPE=ffu-check FFGHR_GIT_MIRROR=git://m/x.git REF_NAME=main FALLBACK=main)" 0
check "says ffbox=true" "$(out ffbox)" true
check "and the branch key" "$(out branch)" main
check "the job's own branch, once" "$(args)" "ffu-check main"

echo "restore, a pull request"
run VERB=restore SCOPE=6000.3.19f1 FFGHR_GIT_MIRROR=git://m/x.git REF_NAME=77/merge HEAD_REF=fix/a BASE_REF=master \
    FALLBACK="master develop" TARGET=win64 >/dev/null
check "its head branch, its base, then the fallbacks, keyed and once each" "$(args)" \
    "--target win64 6000.3.19f1 fix_2fa master develop"
check "the key is the head branch's" "$(out branch)" fix_2fa

echo "restore, a branch named by the caller"
run VERB=restore SCOPE=s FFGHR_GIT_MIRROR=git://m/x.git REF_NAME=main HEAD_REF=x BASE_REF=y BRANCH=release/1 FALLBACK=main >/dev/null
check "that branch, then the fallbacks; not the pull request's base" "$(args)" "s release_2f1 main"

echo "save"
check "exits 0" "$(run VERB=save SCOPE=ffu-check FFGHR_GIT_MIRROR=git://m/x.git REF_NAME=main \
    EXCLUDE=$'./target/tmp\n\n./target/debug/incremental')" 0
check "names <key>@<scope>.tar, with each exclude" "$(args)" \
    "main@ffu-check.tar --exclude=./target/tmp --exclude=./target/debug/incremental"
run VERB=save SCOPE=s FFGHR_GIT_MIRROR=git://m/x.git REF_NAME=main >/dev/null
check "no excludes: the name alone" "$(args)" "main@s.tar"

echo "a failing image step never fails the job"
# shellcheck disable=SC2016  # the fake script's own $1, written literally
printf '#!/usr/bin/env bash\n[ "$1" = branch-key ] && { echo main; exit 0; }\nexit 1\n' > "$tmp/ws"
check "restore" "$(run VERB=restore SCOPE=s FFGHR_GIT_MIRROR=git://m/x.git REF_NAME=main)" 0
check "save" "$(run VERB=save SCOPE=s FFGHR_GIT_MIRROR=git://m/x.git REF_NAME=main)" 0
printf '#!/usr/bin/env bash\nexit 2\n' > "$tmp/ws"
check "an image without branch-key: nothing, exit 0" "$(run VERB=restore SCOPE=s FFGHR_GIT_MIRROR=git://m/x.git REF_NAME=main)" 0

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
