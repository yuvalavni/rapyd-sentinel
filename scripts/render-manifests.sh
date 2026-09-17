#!/usr/bin/env bash
# Render k8s manifests with image coordinates and optional backend NLB hostname.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWNER="${GHCR_OWNER:?set GHCR_OWNER}"
TAG="${IMAGE_TAG:?set IMAGE_TAG}"
BACKEND_HOST="${BACKEND_HOST:-BACKEND_HOST_PLACEHOLDER}"
OUT="${RENDER_DIR:-/tmp/sentinel-k8s}"

rm -rf "${OUT}"
mkdir -p "${OUT}/backend" "${OUT}/gateway"

sed -e "s|GHCR_OWNER|${OWNER}|g" -e "s|IMAGE_TAG|${TAG}|g" \
  "${ROOT}/k8s/backend/backend.yaml" > "${OUT}/backend/backend.yaml"

sed -e "s|GHCR_OWNER|${OWNER}|g" -e "s|IMAGE_TAG|${TAG}|g" \
    -e "s|BACKEND_HOST_PLACEHOLDER|${BACKEND_HOST}|g" \
  "${ROOT}/k8s/gateway/gateway.yaml" > "${OUT}/gateway/gateway.yaml"

echo "Rendered manifests under ${OUT}"
