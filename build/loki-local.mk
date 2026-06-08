##@ Loki local (Docker, no OpenShift / no LLM)

# Minimal plain Loki for exercising loki_label_names and loki_query_range via LOKI_URL.
# Does not cover loki_list_instances (needs LokiStack CRs) or mcpchecker agent evals.

LOKI_LOCAL_PORT ?= 3100
LOKI_LOCAL_URL ?= http://127.0.0.1:$(LOKI_LOCAL_PORT)
LOKI_LOCAL_IMAGE ?= grafana/loki:3.4.2
LOKI_LOCAL_CONTAINER ?= obs-mcp-loki-local
LOKI_LOCAL_READY_TIMEOUT ?= 60
LOKI_LOCAL_LOG_JOB ?= obs-mcp-local

.PHONY: setup-loki-local
setup-loki-local: ## Start Docker Loki and push a test log line (no cluster required)
	@command -v $(CONTAINER_CLI) >/dev/null 2>&1 || { echo "ERROR: $(CONTAINER_CLI) is required"; exit 1; }
	@if curl -sf "$(LOKI_LOCAL_URL)/ready" >/dev/null 2>&1; then \
		echo "Loki already reachable at $(LOKI_LOCAL_URL), pushing test log only"; \
	elif $(CONTAINER_CLI) inspect $(LOKI_LOCAL_CONTAINER) >/dev/null 2>&1; then \
		echo "Starting existing container $(LOKI_LOCAL_CONTAINER)..."; \
		$(CONTAINER_CLI) start $(LOKI_LOCAL_CONTAINER) >/dev/null; \
	else \
		$(CONTAINER_CLI) rm -f $(LOKI_LOCAL_CONTAINER) >/dev/null 2>&1 || true; \
		echo "Starting $(LOKI_LOCAL_IMAGE) as $(LOKI_LOCAL_CONTAINER) on $(LOKI_LOCAL_URL)..."; \
		if ! $(CONTAINER_CLI) run -d --name $(LOKI_LOCAL_CONTAINER) \
			-p $(LOKI_LOCAL_PORT):3100 $(LOKI_LOCAL_IMAGE) >/dev/null 2>&1; then \
			echo "ERROR: failed to start Loki on port $(LOKI_LOCAL_PORT) (in use?). Try: LOKI_LOCAL_PORT=3310 make setup-loki-local"; \
			exit 1; \
		fi; \
	fi
	@elapsed=0; \
	while [ $$elapsed -lt $(LOKI_LOCAL_READY_TIMEOUT) ]; do \
		if curl -sf "$(LOKI_LOCAL_URL)/ready" >/dev/null 2>&1; then \
			echo "Loki ready at $(LOKI_LOCAL_URL)"; \
			break; \
		fi; \
		sleep 2; \
		elapsed=$$((elapsed + 2)); \
	done; \
	if ! curl -sf "$(LOKI_LOCAL_URL)/ready" >/dev/null 2>&1; then \
		echo "ERROR: Loki did not become ready (see: $(CONTAINER_CLI) logs $(LOKI_LOCAL_CONTAINER))"; \
		exit 1; \
	fi
	LOKI_URL="$(LOKI_LOCAL_URL)" LOKI_LOG_JOB="$(LOKI_LOCAL_LOG_JOB)" \
		$(ROOT_DIR)/hack/loki_local/push_test_log.sh

.PHONY: stop-loki-local
stop-loki-local: ## Stop and remove the local Docker Loki container
	@$(CONTAINER_CLI) rm -f $(LOKI_LOCAL_CONTAINER) >/dev/null 2>&1 || true
	@echo "Stopped $(LOKI_LOCAL_CONTAINER) (if it was running)"

.PHONY: run-obs-mcp-local
run-obs-mcp-local: ## Start obs-mcp for local Docker Loki (header auth, logs toolset)
	@$(MAKE) run-obs-mcp-server LOKI_EVAL_TOOLSETS=logs OBS_MCP_AUTH_MODE=header \
		LOKI_URL=$(LOKI_LOCAL_URL) LOKI_USE_ROUTE=false

.PHONY: verify-loki-local
verify-loki-local: ## Smoke-test Loki MCP tools against Docker Loki (obs-mcp on :9100)
	LOKI_URL="$(LOKI_LOCAL_URL)" LOKI_LOG_JOB="$(LOKI_LOCAL_LOG_JOB)" \
		$(ROOT_DIR)/hack/loki_local/verify.sh

.PHONY: run-loki-local-smoke
run-loki-local-smoke: setup-loki-local run-obs-mcp-local ## Full local smoke: Docker Loki + obs-mcp + verify (no OpenShift, no API key)
	@set -e; \
	trap '$(MAKE) stop-obs-mcp-server stop-loki-local' EXIT; \
	$(MAKE) verify-loki-local; \
	echo ""; \
	echo "Local Loki smoke OK. For agent evals use OpenShift: make run-loki-evals (needs OPENAI_API_KEY)."
