.PHONY: dev-start dev-stop dev-clean start-pubsub start-services start-ui

# Development environment variables
PUBSUB_EMULATOR_HOST ?= localhost:8790
PUBSUB_PROJECT_ID ?= gcp-pubsub-456020
CORS_PROXY_PORT ?= 8010

# Start development environment
dev-start:
	@echo "Starting development environment..."
	@ROOT_DIR="$$(pwd)" && \
	export PUBSUB_EMULATOR_HOST=$(PUBSUB_EMULATOR_HOST) && \
	export PUBSUB_PROJECT_ID=$(PUBSUB_PROJECT_ID) && \
	$(MAKE) dev-clean && \
	$(MAKE) start-pubsub && \
	$(MAKE) start-services ROOT_DIR="$$ROOT_DIR" && \
	$(MAKE) start-ui ROOT_DIR="$$ROOT_DIR" && \
	wait

# Start PubSub emulator
start-pubsub:
	@echo "Starting PubSub emulator..."
	@gcloud beta emulators pubsub start --project=$(PUBSUB_PROJECT_ID) --host-port=$(PUBSUB_EMULATOR_HOST) &
	@sleep 5

# Start all services
start-services:
	@echo "Starting services..."
	@cd "$(ROOT_DIR)/service1" && bun run dev &
	@cd "$(ROOT_DIR)/service2" && bun run dev &
	@sleep 2

# Start UI and CORS proxy
start-ui:
	@echo "Starting UI and CORS proxy..."
	@npm install -g local-cors-proxy || true
	@echo "Starting CORS proxy on port $(CORS_PROXY_PORT)..."
	@lsof -t -i:$(CORS_PROXY_PORT) | xargs kill -9 2>/dev/null || true
	@lcp --proxyUrl http://$(PUBSUB_EMULATOR_HOST) --proxyPartial 'proxy' --port $(CORS_PROXY_PORT) &
	@sleep 2
	@cd "$(ROOT_DIR)/pubsub-emulator-ui/webapp" && npm install && npm start &

# Stop development environment
dev-stop:
	@echo "Stopping development environment..."
	@$(MAKE) dev-clean

# Clean up development processes
dev-clean:
	@echo "Cleaning up development processes..."
	@pkill -f "local-cors-proxy" || true
	@pkill -f "bun run" || true
	@pkill -f "pubsub-emulator" || true
	@pkill -f "npm start" || true
	@lsof -t -i:$(CORS_PROXY_PORT) | xargs kill -9 2>/dev/null || true
	@sleep 2
	@echo "Development environment cleaned up!" 