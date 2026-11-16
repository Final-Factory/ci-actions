#!/usr/bin/env bash
# ffbox-workspace.sh -- the workspace action's one step: on an FFBox runner, restore the job's workspace
# from the host's cache before the checkout, or offer it back to the host after the build.
#
# ONE IMPLEMENTATION FOR EVERY REPOSITORY (w4084; lothsahn: "Can it mostly share the same code between
# game CI and FFU CI so that these sorts of differences can't happen?"). The work is the FFBox image's
# /opt/ffghr/ffghr-workspace.sh, the same script for the game's runners and ffu's; this only turns a
# job's branch and inputs into its arguments. The branch key comes from the image too (`branch-key`),
# so no workflow carries a copy of it. The host decides everything that matters: which entries a job may
# read (its pool's own, mounted read-only at /ffcache) and whether a save is granted (only the pool's own
# rebuild-caches.yml on its default branch, by schedule or by hand).
#
# Writes to $GITHUB_OUTPUT:
#   ffbox=true|false   whether this is an FFBox runner (FFGHR_GIT_MIRROR, set only by the FFBox host)
#   branch=<key>       the job's own branch as a cache key (FFBox only)
#
# Env: VERB (restore|save), SCOPE (the cache scope: the Unity version for the game, a job kind for ffu),
# BRANCH (the branch whose entry this is; empty for the job's own: HEAD_REF, else REF_NAME), HEAD_REF
# and BASE_REF (github.head_ref / base_ref), REF_NAME (github.ref_name), FALLBACK (restore: branches to
# try after the job's own and its pull request's base, space or newline separated), TARGET (restore: a
# target cache to try first), EXCLUDE (save: tar patterns relative to the workspace, one per line),
# FFGHR_WORKSPACE (the image's script; overridable for the tests).
#
# Never fails a job for a cache: a missing cache is a cold job, a refused save stages nothing. Only a
# caller's mistake (an unknown verb, no scope) exits non-zero.
set -uo pipefail
ws=${FFGHR_WORKSPACE:-/opt/ffghr/ffghr-workspace.sh}
out=${GITHUB_OUTPUT:-/dev/null}

case "${VERB:-}" in
  restore|save) ;;
  *) echo "::error::workspace: verb must be restore or save, not '${VERB:-}'"; exit 2 ;;
esac
if [ -z "${SCOPE:-}" ]; then
  echo "::error::workspace: scope is required"; exit 2
fi
if [ -z "${FFGHR_GIT_MIRROR:-}" ] || [ ! -x "$ws" ]; then
  echo "ffbox=false" >> "$out"
  echo "not an FFBox runner: no host cache, nothing to $VERB"
  exit 0
fi
echo "ffbox=true" >> "$out"

own=${BRANCH:-${HEAD_REF:-${REF_NAME:-}}}
if [ -z "$own" ]; then
  echo "::warning::workspace: no branch to name the cache by; nothing to $VERB"; exit 0
fi
key=$("$ws" branch-key "$own") || key=
if [ -z "$key" ]; then
  echo "::warning::workspace: the image could not make a cache key of '$own'; nothing to $VERB"; exit 0
fi
echo "branch=$key" >> "$out"

if [ "$VERB" = save ]; then
  args=()
  while IFS= read -r p; do
    [ -n "$p" ] && args+=("--exclude=$p")
  done <<< "${EXCLUDE:-}"
  "$ws" save "$key@$SCOPE.tar" "${args[@]}"
  exit 0
fi

# RESTORE: the job's own branch, its pull request's base, then the fallbacks, each once, in that order.
cands=("$key")
add() {
  local k c
  [ -n "$1" ] || return 0
  k=$("$ws" branch-key "$1") || return 0
  for c in "${cands[@]}"; do [ "$c" = "$k" ] && return 0; done
  cands+=("$k")
}
[ -z "${BRANCH:-}" ] && add "${BASE_REF:-}"
# shellcheck disable=SC2086  # FALLBACK is a list of branch names, split on whitespace on purpose
for b in ${FALLBACK:-}; do add "$b"; done
if [ -n "${TARGET:-}" ]; then
  "$ws" restore --target "$TARGET" "$SCOPE" "${cands[@]}"
else
  "$ws" restore "$SCOPE" "${cands[@]}"
fi
exit 0
