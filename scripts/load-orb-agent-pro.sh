#!/usr/bin/env bash
# Rejoin, verify and load the orb-agent-pro image archives that
# fetch-orb-agent-pro.sh split into parts. Copied into the output directory
# as load.sh; run it from a clone of that directory on the target host.
#
# Usage:  ./load.sh [archive ...]   (default: every *.tar.gz.sha256 here)
# Example: ./load.sh orb-agent-pro_latest_amd64.tar.gz
set -euo pipefail
cd "$(dirname "$0")"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

if [ $# -gt 0 ]; then
  archives=("$@")
else
  archives=()
  for f in *.tar.gz.sha256; do archives+=("${f%.sha256}"); done
fi

for a in "${archives[@]}"; do
  echo "== $a"
  cat "$a".part-* > "$a"
  sha256 -c "$a.sha256"
  docker load -i "$a"
  rm "$a"
done
