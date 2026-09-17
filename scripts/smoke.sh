#!/usr/bin/env bash
# Smoke: public gateway NLB must return the backend body.
set -euo pipefail

REGION="${AWS_REGION:-us-east-2}"
export KUBECONFIG="${HOME}/.kube/sentinel-gateway"

if [[ -f /tmp/sentinel-gateway-nlb ]]; then
  HOST="$(cat /tmp/sentinel-gateway-nlb)"
else
  aws eks update-kubeconfig --name eks-gateway --region "${REGION}" --kubeconfig "${HOME}/.kube/sentinel-gateway"
  HOST="$(kubectl -n sentinel-gateway get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
fi

echo "Curling http://${HOST}/ ..."
ok=0
for i in $(seq 1 36); do
  if body="$(curl -fsS --max-time 10 "http://${HOST}/")"; then
    echo "Response: ${body}"
    if echo "${body}" | grep -q "Hello from backend"; then
      ok=1
      break
    fi
  fi
  echo "waiting for path to become healthy (${i}/36)"
  sleep 10
done

if [[ "${ok}" -ne 1 ]]; then
  echo "Smoke test failed: did not receive 'Hello from backend'" >&2
  exit 1
fi

echo "Smoke test passed."
