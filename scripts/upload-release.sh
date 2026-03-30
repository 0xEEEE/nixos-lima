#!/bin/sh
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <tag>"
  exit 1
fi
NIXOS_LIMA_TAG="$1"
IMAGEDIR="release-${NIXOS_LIMA_TAG}-images"
AARCH64_IMAGE="$IMAGEDIR/nixos-lima-${NIXOS_LIMA_TAG}-aarch64.qcow2"
X86_64_IMAGE="$IMAGEDIR/nixos-lima-${NIXOS_LIMA_TAG}-x86_64.qcow2"
echo "Uploading $AARCH64_IMAGE $X86_64_IMAGE"
gh release upload "$NIXOS_LIMA_TAG" "$AARCH64_IMAGE" "$X86_64_IMAGE"
