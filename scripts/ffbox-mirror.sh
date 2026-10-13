#!/usr/bin/env bash
# ffbox-mirror.sh -- checkout's first step: on an FFBox runner, bring the host's mirror of this
# repository up to the commit the job will check out, and say which commit that is.
#
# Writes to $GITHUB_OUTPUT:
#   ffbox=true|false   whether this is an FFBox runner (FFGHR_GIT_MIRROR, set only by the FFBox host)
#   ref=<sha>          set only when checkout must use another commit than the event's (below)
#
# THE MERGED PULL REQUEST. A pull_request job checks out GitHub's test merge, refs/pull/N/merge, and
# GitHub deletes that ref once the pull request is merged or closed. A job still queued then cannot
# have it: the host fetches and the commit is not there ("fetched <repo>, but <sha> is still not in
# its mirror"). On 2026-10-12 that failed every FFBox job of ff-factory #374, merged while they
# queued. refs/pull/N/head survives the merge, so the job falls back to the pull request's head
# commit, with a warning saying it is testing the head and not the merge. Only for a pull_request
# event and only when the caller did not ask for a ref of its own.
#
# Env: SHA (github.sha), EVENT (github.event_name), HEAD_SHA (the pull request's head commit),
# REF_IN (checkout's ref input), FFGHR_WORKSPACE (the image's script; overridable for the tests).
set -uo pipefail
ws=${FFGHR_WORKSPACE:-/opt/ffghr/ffghr-workspace.sh}
out=${GITHUB_OUTPUT:-/dev/null}

if [ -z "${FFGHR_GIT_MIRROR:-}" ] || [ ! -x "$ws" ]; then
  echo "ffbox=false" >> "$out"
  echo "not an FFBox runner: actions/checkout fetches from GitHub"
  exit 0
fi
echo "ffbox=true" >> "$out"
# The repository must be on the host's extra_mirrors (ffbox config.md) or the host refuses.
if "$ws" use-mirror "$SHA"; then
  exit 0
fi
case "${EVENT:-}" in
  pull_request|pull_request_target) ;;
  *) exit 1 ;;
esac
if [ -n "${REF_IN:-}" ] || ! [[ "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || [ "$HEAD_SHA" = "$SHA" ]; then
  exit 1
fi
echo "::warning::the pull request's test merge ($SHA) is gone, so it was merged or closed before this job started; testing its head commit ($HEAD_SHA) instead"
"$ws" use-mirror "$HEAD_SHA" || exit 1
echo "ref=$HEAD_SHA" >> "$out"
