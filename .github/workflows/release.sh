#!/usr/bin/env bash

set -euxo pipefail

IMAGE="ghcr.io/${GITHUB_REPOSITORY}:${GITHUB_REF_NAME}"
OUTPUT_PREFIX="image-${GITHUB_REF_NAME}"

PLATFORMS=("linux/amd64" "linux/arm64")

for PLATFORM in "${PLATFORMS[@]}"; do
  ARCH="${PLATFORM#*/}"
  OUTPUT_TAR="${OUTPUT_PREFIX}-${ARCH}.tar"

  echo "Pulling image: ${IMAGE} for ${PLATFORM}"
  docker pull --platform "${PLATFORM}" "${IMAGE}"

  echo "Saving image to tar: ${OUTPUT_TAR}"
  docker save "${IMAGE}" -o "${OUTPUT_TAR}"

  echo "Image saved to ${OUTPUT_TAR}"
done
