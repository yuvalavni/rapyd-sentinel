#!/usr/bin/env bash
# Deploy backend then gateway. Gateway upstream is the backend internal NLB DNS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-us-east-2}"
OWNER="${GHCR_OWNER:?set GHCR_OWNER}"
TAG="${IMAGE_TAG:?set IMAGE_TAG}"
RENDER_DIR="${RENDER_DIR:-/tmp/sentinel-k8s}"

export GHCR_OWNER OWNER IMAGE_TAG TAG RENDER_DIR

"${ROOT}/scripts/render-manifests.sh"

echo "==> kubeconfig for eks-backend"
aws eks update-kubeconfig --name eks-backend --region "${REGION}" --kubeconfig "${HOME}/.kube/sentinel-backend"
echo "==> kubeconfig for eks-gateway"
aws eks update-kubeconfig --name eks-gateway --region "${REGION}" --kubeconfig "${HOME}/.kube/sentinel-gateway"

if [[ -n "${GHCR_TOKEN:-}" ]]; then
  echo "==> imagePullSecret for private GHCR packages"
  for ctx in sentinel-backend sentinel-gateway; do
    ns="sentinel-backend"
    [[ "${ctx}" == "sentinel-gateway" ]] && ns="sentinel-gateway"
    export KUBECONFIG="${HOME}/.kube/${ctx}"
    kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n "${ns}" create secret docker-registry ghcr \
      --docker-server=ghcr.io \
      --docker-username="${GHCR_OWNER}" \
      --docker-password="${GHCR_TOKEN}" \
      --dry-run=client -o yaml | kubectl apply -f -
  done
fi

inject_pull_secret() {
  local f="$1"
  python3 - "${f}" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
needle = "      containers:"
inject = "      imagePullSecrets:\n        - name: ghcr\n      containers:"
if "imagePullSecrets:" not in text:
    text = text.replace(needle, inject, 1)
    p.write_text(text)
PY
}

echo "==> apply backend"
export KUBECONFIG="${HOME}/.kube/sentinel-backend"
if [[ -n "${GHCR_TOKEN:-}" ]]; then
  inject_pull_secret "${RENDER_DIR}/backend/backend.yaml"
fi
kubectl apply -f "${RENDER_DIR}/backend/backend.yaml"
kubectl -n sentinel-backend rollout status deployment/backend --timeout=180s

echo "==> wait for internal NLB"
for i in $(seq 1 60); do
  BACKEND_HOST="$(kubectl -n sentinel-backend get svc backend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -n "${BACKEND_HOST}" ]]; then
    echo "Backend NLB: ${BACKEND_HOST}"
    break
  fi
  sleep 10
done
if [[ -z "${BACKEND_HOST:-}" ]]; then
  echo "Timed out waiting for backend internal NLB hostname" >&2
  kubectl -n sentinel-backend get svc backend -o yaml >&2 || true
  exit 1
fi

export BACKEND_HOST
"${ROOT}/scripts/render-manifests.sh"

echo "==> apply gateway (upstream ${BACKEND_HOST})"
export KUBECONFIG="${HOME}/.kube/sentinel-gateway"
if [[ -n "${GHCR_TOKEN:-}" ]]; then
  inject_pull_secret "${RENDER_DIR}/gateway/gateway.yaml"
fi
kubectl apply -f "${RENDER_DIR}/gateway/gateway.yaml"
kubectl -n sentinel-gateway rollout status deployment/gateway --timeout=180s

echo "==> wait for public NLB"
for i in $(seq 1 60); do
  GATEWAY_HOST="$(kubectl -n sentinel-gateway get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -n "${GATEWAY_HOST}" ]]; then
    echo "Gateway NLB: ${GATEWAY_HOST}"
    echo "${GATEWAY_HOST}" > /tmp/sentinel-gateway-nlb
    break
  fi
  sleep 10
done
if [[ -z "${GATEWAY_HOST:-}" ]]; then
  echo "Timed out waiting for gateway public NLB hostname" >&2
  kubectl -n sentinel-gateway get svc gateway -o yaml >&2 || true
  exit 1
fi
