#!/usr/bin/env bash
# Pull orb-agent-pro images for one platform, save each as a gzipped docker
# archive and split it into parts small enough for a GitHub repo (GitHub
# rejects files over 100 MiB). The output directory is self-contained: copy it
# to the repo; on the target host run ./load.sh in a clone of it.
#
# Usage:  scripts/fetch-orb-agent-pro.sh [tag ...]     (default: develop latest)
#
# Environment:
#   PLATFORM     target platform                 (default linux/amd64)
#   OUT_DIR      output directory                (default images)
#   CHUNK_SIZE   size of each part, split syntax (default 95m)
#   QUAY_USER, QUAY_TOKEN
#                optional; if both are set the script logs in to quay.io.
#                Otherwise run `docker login quay.io` before this script.
set -euo pipefail

REPO=quay.io/netboxlabs/orb-agent-pro
PLATFORM=${PLATFORM:-linux/amd64}
OUT_DIR=${OUT_DIR:-images}
CHUNK_SIZE=${CHUNK_SIZE:-95m}
ARCH=${PLATFORM#*/}
if [ $# -gt 0 ]; then TAGS=("$@"); else TAGS=(develop latest); fi
HERE=$(cd "$(dirname "$0")" && pwd)

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

if [ -n "${QUAY_USER:-}" ] && [ -n "${QUAY_TOKEN:-}" ]; then
  printf '%s' "$QUAY_TOKEN" | docker login quay.io -u "$QUAY_USER" --password-stdin
fi

mkdir -p "$OUT_DIR"
# Each run replaces every archive in OUT_DIR, so the folder always matches
# MANIFEST.txt. Pass every tag you want to keep.
rm -f "$OUT_DIR"/orb-agent-pro_*.tar.gz "$OUT_DIR"/orb-agent-pro_*.tar.gz.part-* "$OUT_DIR"/orb-agent-pro_*.tar.gz.sha256
cp "$HERE/load-orb-agent-pro.sh" "$OUT_DIR/load.sh"
chmod +x "$OUT_DIR/load.sh"

MANIFEST="$OUT_DIR/MANIFEST.txt"
{
  echo "orb-agent-pro images for $PLATFORM, fetched $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Load on the target host with: ./load.sh"
} > "$MANIFEST"

for tag in "${TAGS[@]}"; do
  ref="$REPO:$tag"
  name="orb-agent-pro_${tag}_${ARCH}.tar.gz"
  echo "== $ref ($PLATFORM)"

  # Retry: large pulls can die on a network or DNS hiccup. Finished layers
  # are kept, so each retry only fetches what is missing.
  for attempt in 1 2 3 4 5; do
    if docker pull --platform "$PLATFORM" "$ref"; then break; fi
    if [ "$attempt" -eq 5 ]; then echo "error: pull of $ref failed 5 times" >&2; exit 1; fi
    echo "pull failed (attempt $attempt), retrying in $((attempt * 10))s" >&2
    sleep $((attempt * 10))
  done

  got=$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$ref")
  if [ "$got" != "$PLATFORM" ]; then
    echo "error: local $ref is $got, expected $PLATFORM" >&2
    exit 1
  fi
  digests=$(docker image inspect --format '{{join .RepoDigests " "}}' "$ref")

  # Read package versions from the image filesystem, so this also works when
  # the target platform cannot run on this machine.
  cid=$(docker create --platform "$PLATFORM" "$ref")
  versions=$(docker export "$cid" | tar -tf - \
    | sed -nE 's#.*site-packages/(netboxlabs_diode_sdk|nbl_cisco_catalyst_center|netboxlabs_orb_worker)-([^/]+)\.dist-info/.*#\1 \2#p' \
    | sort -u)
  docker rm "$cid" >/dev/null
  agent=$(docker run --rm --platform "$PLATFORM" --entrypoint orb-agent "$ref" version 2>/dev/null \
    || echo "unknown (cannot run $PLATFORM here)")

  echo "saving $name"
  docker save "$ref" | gzip > "$OUT_DIR/$name"
  (cd "$OUT_DIR" && sha256 "$name" > "$name.sha256")
  size=$(wc -c < "$OUT_DIR/$name" | tr -d ' ')

  split -a 3 -b "$CHUNK_SIZE" "$OUT_DIR/$name" "$OUT_DIR/$name.part-"
  rm "$OUT_DIR/$name"
  parts=$(cd "$OUT_DIR" && ls "$name".part-* | wc -l | tr -d ' ')

  {
    echo
    echo "[$ref]"
    echo "platform:  $got"
    echo "digest:    $digests"
    echo "orb-agent: $agent"
    echo "$versions" | sed 's/^/package:   /'
    echo "archive:   $name ($size bytes, $parts parts of $CHUNK_SIZE)"
    echo "sha256:    $(cut -d' ' -f1 "$OUT_DIR/$name.sha256")"
  } >> "$MANIFEST"
done

echo
cat "$MANIFEST"
