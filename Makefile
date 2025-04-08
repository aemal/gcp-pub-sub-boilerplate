.PHONY: setup dev clean check-jq

# Include development makefile
include scripts/dev.mk

# Default target
all: check-jq

# Check for required dependencies
check-jq:
	@if ! command -v jq &> /dev/null; then \
		echo "Error: jq is required but not installed. Please install it first."; \
		echo "macOS: brew install jq"; \
		echo "Ubuntu/Debian: sudo apt-get install jq"; \
		exit 1; \
	fi

# Setup GCP infrastructure
setup: check-jq
	@./scripts/setup-gcp.sh

# Start development environment
dev: check-jq dev-start

# Clean up processes
clean: dev-clean
	@echo "Cleanup complete!" 