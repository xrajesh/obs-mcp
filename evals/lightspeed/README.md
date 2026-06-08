# Lightspeed Evals

The evaluations testset for the obs-mcp based on [lightspeed-evaluation](https://github.com/lightspeed-core/lightspeed-evaluation).

## Configuration Files

| File | Description |
|------|-------------|
| `system.yaml` | System prompt and LLM configuration |
| `evals.yaml` | Default test cases — **metrics + traces only** (safe on a standard OpenShift cluster with monitoring) |
| `evals-loki.yaml` | Opt-in Loki tests — requires the [Loki test fixture](#loki-evals-opt-in-fixture) |

## Pre-requisites

- [uv](https://docs.astral.sh/uv/)
- OpenShift cluster with:
  - Thanos Querier or Prometheus accessible (built into OpenShift monitoring)
  - For **traces** evals: Tempo stack from `hack/e2e/setup.sh --stacks tempo`
  - For **Loki** evals: separate fixture — see below (Loki is **not** installed on OpenShift by default)
  - Valid kubeconfig or service account credentials
- obs-mcp server running with the toolsets your evals need — see [README](../../README.md) and [DEPLOYMENT.md](../../docs/DEPLOYMENT.md)
- OpenAI API key

## Quickstart

### Install dependencies

```bash
uv sync
```

### Setup the lightspeed-stack

On another terminal:

```shell
git clone https://github.com/lightspeed-core/lightspeed-stack.git
cd lightspeed-stack
```

Copy the lightspeed configs from this [repo](../../hack/lightspeed-stack) to the stack directory.

**Note:** Adjust the path where obs-mcp is located accordingly in the below command.

```shell
cp ../obs-mcp/hack/lightspeed-stack/lightspeed-stack.yaml lightspeed-stack.yaml
cp ../obs-mcp/hack/lightspeed-stack/run.yaml run.yaml
```

```shell
uv sync --group dev --group llslibdev
export OPENAI_API_KEY="your-api-key-here"
make run
```

### Provision observability backends (recommended)

Use `hack/e2e/setup.sh` so eval backends match the test expectations (same model as [PR #112](https://github.com/rhobs/obs-mcp/pull/112)):

```bash
# From obs-mcp repo root — metrics + traces (default stacks)
oc login …
hack/e2e/setup.sh up --profile openshift --stacks prometheus,tempo

# Add Loki fixture for logs evals (OpenShift only; 10–20 min first time)
hack/e2e/setup.sh up --profile openshift --stacks prometheus,tempo,loki
```

Equivalent Make targets for Loki-only fixture work: `make setup-loki-evals`, `make run-loki-mcp-server LOKI_MCP_TOOLSETS=logs`.

### Run the evaluations (default — no Loki)

The default `evals.yaml` does **not** include Loki tests. It will not fail on a fresh OpenShift cluster that has monitoring but no Loki Operator.

> [!TIP]
>
> Keep `.caches` when tweaking evaluation criteria to avoid re-running expensive LLM calls.

```bash
export OPENAI_API_KEY="your-api-key-here"
rm -rf .caches   # optional: drop when changing criteria

# All default evals (metrics + traces groups)
uv run lightspeed-eval --system-config system.yaml --eval-data evals.yaml

# Or filter by stack tag
uv run lightspeed-eval --system-config system.yaml --eval-data evals.yaml --tags metrics
uv run lightspeed-eval --system-config system.yaml --eval-data evals.yaml --tags traces
```

## Loki evals (opt-in fixture)

Loki is **not** part of default OpenShift. The Loki conversation groups target a **reproducible test stack**, not an arbitrary cluster:

| Fixture | What it provides |
|---------|------------------|
| LokiStack `obs-mcp-loki` in namespace `obs-mcp-loki` | `loki_list_instances`, gateway queries |
| Tenant `network` | Multi-tenant LokiStack routing |
| NetObserv-shaped labels (`SrcK8S_Namespace`, …) | Flow-log query evals (optional; needs FlowCollector or hack log generator + RBAC) |

**Provision the fixture** (pick one):

```bash
# Via unified e2e setup (OpenShift)
hack/e2e/setup.sh up --profile openshift --stacks loki

# Or Makefile / hack script directly
make setup-loki-evals
```

**Run obs-mcp** with the `logs` toolset (and `--loki.use-route` or port-forward — see [hack/loki_multitenancy_openshift/README.md](../../hack/loki_multitenancy_openshift/README.md)).

**Run Loki lightspeed evals:**

```bash
export OPENAI_API_KEY="your-api-key-here"

# LokiStack discovery (loki-list-instances)
uv run lightspeed-eval --system-config system.yaml --eval-data evals-loki.yaml --tags loki-fixture

# NetObserv flow log query (loki-query-network-flows) — needs flow log data in tenant network
uv run lightspeed-eval --system-config system.yaml --eval-data evals-loki.yaml --tags loki-netobserv
```

**Without OpenShift or LLM:** basic Loki tool smoke only (not these agent evals):

```bash
make run-loki-local-smoke   # Docker Loki + MCP verify; see hack/loki_local/README.md
```

See also [mcpchecker Loki evals](../mcpchecker/README.md#loki-logs-evals-openshift).
