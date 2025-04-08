.PHONY: setup-gcp check-env

# Load environment variables
include ../.env

# Check environment variables
check-env:
	@if [ -z "$(PROJECT_ID)" ]; then \
		echo "Error: PROJECT_ID environment variable is not set"; \
		exit 1; \
	fi

# Setup GCP Pub/Sub infrastructure
setup-gcp: check-env
	@echo "Setting up GCP Pub/Sub infrastructure for project: $(PROJECT_ID)"
	@if [ ! -f "config/pubsub-config.json" ]; then \
		echo "Error: Configuration file config/pubsub-config.json not found"; \
		exit 1; \
	fi
	@PUBLISHER_SA="$(PROJECT_ID).appspot.com" \
	SUBSCRIBER_SA="$(PROJECT_ID).appspot.com" \
	./scripts/setup-gcp.sh 