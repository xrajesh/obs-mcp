##@ Loki evals (OpenShift + mcpchecker)

# Loki eval tasks expect LokiStack obs-mcp-loki in namespace obs-mcp-loki (see hack/loki_multitenancy_openshift/).
# Requires: oc login, default StorageClass, OPENAI_API_KEY for agent evals.

LOKI_EVAL_HACK_DIR := hack/loki_multitenancy_openshift
LOKI_EVAL_INSTALL := $(LOKI_EVAL_HACK_DIR)/install
OBS_MCP_PORT ?= 9100
OBS_MCP_PID_FILE ?= .obs-mcp.pid
OBS_MCP_HEALTH_TIMEOUT ?= 60
OBS_MCP_HEALTH_INTERVAL ?= 2
LOKI_EVAL_TOOLSETS ?= logs
LOKI_USE_ROUTE ?= true
OBS_MCP_AUTH_MODE ?= kubeconfig

.PHONY: setup-loki-evals
setup-loki-evals: ## Deploy Loki operator test stack on OpenShift (no obs-mcp required)
	@test -n "$$(oc whoami 2>/dev/null)" || { echo "ERROR: oc login required"; exit 1; }
	$(ROOT_DIR)/hack/e2e/setup.sh extras --profile openshift --stacks loki

.PHONY: verify-loki-evals
verify-loki-evals: ## Smoke-test Loki MCP tools via 03_verify.sh (obs-mcp must be running on :9100)
	$(LOKI_EVAL_HACK_DIR)/03_verify.sh

.PHONY: run-obs-mcp-server
run-obs-mcp-server: build ## Start obs-mcp in background for evals (logs toolset, port $(OBS_MCP_PORT))
	@if [ -f $(OBS_MCP_PID_FILE) ] && kill -0 $$(cat $(OBS_MCP_PID_FILE)) 2>/dev/null; then \
		echo "obs-mcp already running (PID $$(cat $(OBS_MCP_PID_FILE)))"; \
		exit 0; \
	fi
	@echo "Starting obs-mcp on 127.0.0.1:$(OBS_MCP_PORT) with toolsets=$(LOKI_EVAL_TOOLSETS)..."
	@LOKI_ARGS=""; \
	if [ -n "$(LOKI_URL)" ]; then LOKI_ARGS="--loki-url $(LOKI_URL)"; \
	elif [ "$(LOKI_USE_ROUTE)" = "true" ]; then LOKI_ARGS="--loki.use-route"; fi; \
	./obs-mcp --listen 127.0.0.1:$(OBS_MCP_PORT) --auth-mode $(OBS_MCP_AUTH_MODE) --insecure \
		--log-level $(LOG_LEVEL) --toolsets $(LOKI_EVAL_TOOLSETS) $$LOKI_ARGS \
		>/tmp/obs-mcp-eval.log 2>&1 & echo $$! > $(OBS_MCP_PID_FILE)
	@elapsed=0; \
	while [ $$elapsed -lt $(OBS_MCP_HEALTH_TIMEOUT) ]; do \
		if curl -sf "http://127.0.0.1:$(OBS_MCP_PORT)/health" >/dev/null 2>&1; then \
			echo "obs-mcp ready at http://127.0.0.1:$(OBS_MCP_PORT)/mcp"; \
			exit 0; \
		fi; \
		sleep $(OBS_MCP_HEALTH_INTERVAL); \
		elapsed=$$((elapsed + $(OBS_MCP_HEALTH_INTERVAL))); \
	done; \
	echo "ERROR: obs-mcp failed to start (see /tmp/obs-mcp-eval.log)"; exit 1

.PHONY: stop-obs-mcp-server
stop-obs-mcp-server: ## Stop obs-mcp started by run-obs-mcp-server
	@if [ -f $(OBS_MCP_PID_FILE) ]; then \
		PID=$$(cat $(OBS_MCP_PID_FILE)); \
		echo "Stopping obs-mcp (PID: $$PID)"; \
		kill $$PID 2>/dev/null || true; \
		rm -f $(OBS_MCP_PID_FILE); \
	else \
		echo "No $(OBS_MCP_PID_FILE) found"; \
	fi

.PHONY: run-loki-evals
run-loki-evals: setup-loki-evals run-obs-mcp-server $(TOOLS_BIN_DIR)/mcpchecker ## Full Loki eval flow: stack + obs-mcp + mcpchecker (needs OPENAI_API_KEY)
	@set -e; \
	trap '$(MAKE) stop-obs-mcp-server' EXIT; \
	$(MAKE) verify-loki-evals; \
	$(MAKE) run-mcpchecker-eval CATEGORY=logs EVAL_CONFIG=eval-logs.yaml; \
	echo ""; \
	echo "Loki evals finished. Target pass rate: >= 80% tasks and assertions."

.PHONY: teardown-loki-evals
teardown-loki-evals: stop-obs-mcp-server ## Remove Loki eval test stack from OpenShift
	oc delete -f $(LOKI_EVAL_HACK_DIR)/03_lokistack.yaml --ignore-not-found
	oc delete -f $(LOKI_EVAL_INSTALL)/ --ignore-not-found
	oc delete clusterrole/obs-mcp-loki-gateway-read --ignore-not-found
