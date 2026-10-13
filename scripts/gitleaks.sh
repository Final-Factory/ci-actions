#!/usr/bin/env bash
# gitleaks.sh VERSION FFBOX -- gitleaks VERSION on the PATH, or a failed step that says why.
#
# Already there at that version: used as it is (the FFBox image bakes it, checksum-verified at build).
# On FFBox otherwise: fail, since a container there cannot reach github.com. Anywhere else: download
# the release for this OS and CPU, check it against the release's own checksums file, and put it on
# GITHUB_PATH.
set -euo pipefail
want=${1:?gitleaks version} ffbox=${2:-false}
have=$(gitleaks version 2>/dev/null | sed 's/^v//' || true)
if [ "$have" = "$want" ]; then echo "gitleaks $have on the runner"; exit 0; fi
if [ "$ffbox" = true ]; then
  echo "::error::the FFBox runner image has gitleaks ${have:-none}, not $want: bump GITLEAKS_VERSION in ffbox scripts/Dockerfile"
  exit 1
fi
case "$RUNNER_OS" in Linux) os=linux ;; macOS) os=darwin ;; *) echo "::error::gitleaks install not supported on $RUNNER_OS"; exit 1 ;; esac
case "$RUNNER_ARCH" in X64) arch=x64 ;; ARM64) arch=arm64 ;; *) echo "::error::gitleaks install not supported on $RUNNER_ARCH"; exit 1 ;; esac
file="gitleaks_${want}_${os}_${arch}.tar.gz"
base="https://github.com/gitleaks/gitleaks/releases/download/v${want}"
dir="$RUNNER_TEMP/gitleaks-$want"
mkdir -p "$dir"
curl -fsSL --retry 3 -o "$dir/$file" "$base/$file"
curl -fsSL --retry 3 -o "$dir/checksums.txt" "$base/gitleaks_${want}_checksums.txt"
expected=$(awk -v f="$file" '$2 == f { print $1 }' "$dir/checksums.txt")
[ -n "$expected" ] || { echo "::error::$file is not in the release's checksums file"; exit 1; }
actual=$( (sha256sum "$dir/$file" 2>/dev/null || shasum -a 256 "$dir/$file") | cut -d' ' -f1)
[ "$actual" = "$expected" ] || { echo "::error::$file does not match its checksum ($actual, want $expected)"; exit 1; }
tar -xzf "$dir/$file" -C "$dir" gitleaks
echo "$dir" >> "$GITHUB_PATH"
"$dir/gitleaks" version
