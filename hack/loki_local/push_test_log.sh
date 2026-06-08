#!/usr/bin/env bash
set -euo pipefail

LOKI_URL="${LOKI_URL:-http://127.0.0.1:3100}"
LOKI_LOG_JOB="${LOKI_LOG_JOB:-obs-mcp-local}"
LOKI_LOG_NAMESPACE="${LOKI_LOG_NAMESPACE:-default}"
LOKI_LOG_MESSAGE="${LOKI_LOG_MESSAGE:-obs-mcp local smoke test log line}"

ts_ns="$(date +%s)000000000"
payload="$(jq -nc \
  --arg ts "${ts_ns}" \
  --arg job "${LOKI_LOG_JOB}" \
  --arg ns "${LOKI_LOG_NAMESPACE}" \
  --arg msg "${LOKI_LOG_MESSAGE}" \
  '{streams:[{stream:{job:$job,namespace:$ns},values:[[$ts,$msg]]}]}')"

curl -sf -H "Content-Type: application/json" \
  -X POST "${LOKI_URL}/loki/api/v1/push" \
  --data-raw "${payload}" >/dev/null

echo "Pushed test log to ${LOKI_URL} (job=${LOKI_LOG_JOB}, namespace=${LOKI_LOG_NAMESPACE})"
