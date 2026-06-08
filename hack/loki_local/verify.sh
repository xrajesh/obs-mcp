#!/usr/bin/env bash
set -euo pipefail

MCP_URL="${MCP_URL:-http://127.0.0.1:9100/mcp}"
LOKI_URL="${LOKI_URL:-http://127.0.0.1:3100}"
LOKI_LOG_JOB="${LOKI_LOG_JOB:-obs-mcp-local}"
LOKI_QUERY="${LOKI_QUERY:-{job=\"${LOKI_LOG_JOB}\"}}"
VERIFY_DURATION="${VERIFY_DURATION:-15m}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-5}"
CURL_MCP_MAX_TIME="${CURL_MCP_MAX_TIME:-120}"
LOKI_QUERY_MAX_ATTEMPTS="${LOKI_QUERY_MAX_ATTEMPTS:-12}"
LOKI_QUERY_SLEEP="${LOKI_QUERY_SLEEP:-2}"

mcp_parse_sse() {
  local body="$1"
  if [[ "${body}" == *$'\ndata:'* ]] || [[ "${body}" == data:* ]]; then
    printf '%s\n' "${body}" | awk '/^data: / { sub(/^data: /, ""); print; exit }'
    return
  fi
  printf '%s' "${body}"
}

mcp_call_raw() {
  local payload="$1"
  local raw result
  if ! raw="$(curl -sS --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MCP_MAX_TIME}" \
    -X POST "${MCP_URL}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "${payload}")"; then
    echo "ERROR: MCP request to ${MCP_URL} failed" >&2
    echo "Start obs-mcp first: make run-obs-mcp-local" >&2
    exit 1
  fi
  result="$(mcp_parse_sse "${raw}")"
  if [[ -z "${result}" ]]; then
    echo "ERROR: MCP response contained no JSON payload:" >&2
    echo "${raw}" >&2
    exit 1
  fi
  if ! echo "${result}" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: MCP response is not valid JSON:" >&2
    echo "${raw}" >&2
    exit 1
  fi
  if echo "${result}" | jq -e '.error' >/dev/null 2>&1; then
    echo "ERROR: MCP tool call returned an error:" >&2
    echo "${result}" | jq . >&2
    exit 1
  fi
  if echo "${result}" | jq -e '.result.isError == true' >/dev/null 2>&1; then
    echo "ERROR: MCP tool call returned isError=true:" >&2
    echo "${result}" | jq . >&2
    exit 1
  fi
  printf '%s' "${result}"
}

mcp_call() {
  local result
  result="$(mcp_call_raw "$1")"
  echo "${result}" | jq .
}

echo "==> Checking Loki at ${LOKI_URL}"
curl -sf "${LOKI_URL}/ready" >/dev/null || {
  echo "ERROR: Loki not reachable at ${LOKI_URL}" >&2
  echo "Run: make setup-loki-local" >&2
  exit 1
}
echo "OK: Loki /ready"

echo "==> Ensuring test log exists (job=${LOKI_LOG_JOB})"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOKI_URL="${LOKI_URL}" LOKI_LOG_JOB="${LOKI_LOG_JOB}" "${SCRIPT_DIR}/push_test_log.sh"

echo "==> MCP call: loki_label_names (direct LOKI_URL, no LokiStack)"
LABELS_RESULT="$(mcp_call_raw '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"loki_label_names","arguments":{}}}')"
echo "${LABELS_RESULT}" | jq .
if ! echo "${LABELS_RESULT}" | jq -e '.result.structuredContent.labels | index("job")' >/dev/null 2>&1; then
  echo "ERROR: expected label 'job' in loki_label_names response" >&2
  exit 1
fi
echo "OK: loki_label_names includes job"

echo "==> MCP call: loki_query_range"
echo "    query: ${LOKI_QUERY}"
QUERY_PAYLOAD="$(jq -nc \
  --arg query "${LOKI_QUERY}" \
  --arg duration "${VERIFY_DURATION}" \
  '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:"loki_query_range",arguments:{query:$query,duration:$duration,limit:20}}}')"
QUERY_RESULT=""
STREAM_COUNT=0
for attempt in $(seq 1 "${LOKI_QUERY_MAX_ATTEMPTS}"); do
  QUERY_RESULT="$(mcp_call_raw "${QUERY_PAYLOAD}")"
  STREAM_COUNT="$(echo "${QUERY_RESULT}" | jq -r '.result.structuredContent.streams | length // 0')"
  if [[ "${STREAM_COUNT}" != "0" ]]; then
    echo "${QUERY_RESULT}" | jq .
    echo "OK: query returned ${STREAM_COUNT} stream(s) (attempt ${attempt}/${LOKI_QUERY_MAX_ATTEMPTS})"
    break
  fi
  echo "Waiting for indexed logs (${attempt}/${LOKI_QUERY_MAX_ATTEMPTS})..."
  sleep "${LOKI_QUERY_SLEEP}"
done
if [[ "${STREAM_COUNT}" == "0" ]]; then
  echo "ERROR: loki_query_range returned no streams for ${LOKI_QUERY}" >&2
  echo "${QUERY_RESULT}" | jq . >&2
  exit 1
fi

echo ""
echo "Local Loki MCP smoke passed (label_names + query_range via --loki-url)."
echo "Note: loki_list_instances requires a cluster with LokiStack CRs (OpenShift eval stack)."
