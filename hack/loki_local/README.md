# Local Loki smoke (Docker)

Minimal setup to exercise obs-mcp **logs** tools without OpenShift or an LLM API key.

Uses plain [Grafana Loki](https://grafana.com/oss/loki/) in Docker and `--loki-url` (no Loki Operator / `loki_list_instances`).

## Quick start

```bash
make run-loki-local-smoke
```

This starts Docker Loki, pushes a test log line, runs obs-mcp on `:9100` with `--toolsets logs`, and verifies `loki_label_names` + `loki_query_range` via MCP.

## Step by step

```bash
make setup-loki-local          # docker run grafana/loki, push test log
make run-obs-mcp-local         # obs-mcp with header auth + --loki-url
make verify-loki-local         # MCP smoke (no OPENAI_API_KEY)
make stop-obs-mcp-server       # when done
make stop-loki-local
```

## What this does not cover

| Feature | Local Docker | OpenShift eval stack |
|---------|--------------|----------------------|
| `loki_label_names` / `loki_query_range` via `LOKI_URL` | Yes | Yes |
| `loki_list_instances` (LokiStack CRs) | No | Yes |
| mcpchecker agent evals (`eval-logs.yaml`) | No (needs `OPENAI_API_KEY` + LokiStack) | Yes |

For full agent evals see [`evals/mcpchecker/README.md`](../../evals/mcpchecker/README.md#loki-logs-evals-openshift).

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `LOKI_LOCAL_PORT` | `3100` | Host port for Docker Loki |
| `LOKI_LOCAL_IMAGE` | `grafana/loki:3.4.2` | Container image |
| `LOKI_LOG_JOB` | `obs-mcp-local` | Label on pushed test logs |
| `MCP_URL` | `http://127.0.0.1:9100/mcp` | obs-mcp endpoint for verify |

If port `3100` is already in use, set `LOKI_LOCAL_PORT=3310` (or any free port) for all targets.
