# Default environment is 'dev'
ENV ?= dev

# Check and set appropriate environment based on PROJECT_ID if ENV not explicitly set
define detect_environment
	@if [ "$(ENV)" = "dev" ] && [ -n "$(PROJECT_ID)" ]; then \
		if echo "$(PROJECT_ID)" | grep -q "prod"; then \
			echo "Detected production project ID, setting ENV=prod"; \
			ENV=prod; \
		elif echo "$(PROJECT_ID)" | grep -q "staging"; then \
			echo "Detected staging project ID, setting ENV=staging"; \
			ENV=staging; \
		else \
			echo "Using default environment: dev"; \
		fi; \
	fi
endef

# Environment-specific base URLs
DEV_BASE_URL := https://example.com
STAGING_BASE_URL := https://staging-api.example.com
PROD_BASE_URL := https://api.example.com

# Set the base URL based on the environment
ifeq ($(ENV),dev)
	BASE_URL := $(DEV_BASE_URL)
else ifeq ($(ENV),staging)
	BASE_URL := $(STAGING_BASE_URL)
else ifeq ($(ENV),prod)
	BASE_URL := $(PROD_BASE_URL)
else
	# Default to dev if an invalid environment is specified
	BASE_URL := $(DEV_BASE_URL)
endif

.PHONY: dev clean check-docker start-emulator sync-from-gcp sync-to-gcp dev-force-sync

# Source environment variables
include .env
export

# Check if gcloud is installed
GCLOUD := $(shell command -v gcloud 2> /dev/null)
ifndef GCLOUD
    $(error "gcloud is not installed. Please install Google Cloud SDK.")
endif

# Check if jq is installed
JQ := $(shell command -v jq 2> /dev/null)
ifndef JQ
    $(error "jq is not installed. Please install jq.")
endif

# Check if local config has been modified
check-local-config:
	@if [ -f "config/pubsub-config.json" ]; then \
		if git diff --quiet config/pubsub-config.json 2>/dev/null; then \
			echo "Local config is unchanged, syncing from GCP..."; \
			$(MAKE) sync-from-gcp; \
		else \
			echo "Local config has been modified, preserving changes..."; \
		fi \
	else \
		echo "No local config found, syncing from GCP..."; \
		$(MAKE) sync-from-gcp; \
	fi

# Default dev target: Preserves local config changes by default, then syncs to GCP
dev: check-docker check-local-config start-emulator sync-to-gcp
	pkill -f "bun.*src/index.ts" || true
	pkill -f "bun.*service1/src/index.ts" || true
	pkill -f "bun.*service2/src/index.ts" || true
	bun install
	cd service1 && bun install
	cd service2 && bun install
	bun run dev & \
		cd service1 && bun run dev & \
		cd service2 && bun run dev

# New target: Explicitly sync from GCP first, overwriting local changes, then sync back
dev-force-sync: check-docker sync-from-gcp start-emulator sync-to-gcp
	pkill -f "bun.*src/index.ts" || true
	pkill -f "bun.*service1/src/index.ts" || true
	pkill -f "bun.*service2/src/index.ts" || true
	bun install
	cd service1 && bun install
	cd service2 && bun install
	bun run dev & \
		cd service1 && bun run dev & \
		cd service2 && bun run dev

check-docker:
	@if ! docker info > /dev/null 2>&1; then \
		echo "Error: Docker is not running. Please start Docker and try again."; \
		exit 1; \
	fi

start-emulator: check-docker
	@echo "Starting PubSub emulator..."
	docker stop pubsub-emulator || true
	docker rm pubsub-emulator || true
	docker run --rm -d \
		-p 8085:8085 \
		--name pubsub-emulator \
		--add-host=host.docker.internal:host-gateway \
		google/cloud-sdk:latest \
		gcloud beta emulators pubsub start --host-port=0.0.0.0:8085
	sleep 5  # Give the emulator time to start
	@echo "Checking PubSub emulator..."
	@while ! curl -s http://localhost:8085 > /dev/null; do \
		echo "Waiting for PubSub emulator to be ready..."; \
		sleep 2; \
	done
	@echo "PubSub emulator is ready!"

sync-from-gcp:
	@echo "Syncing configuration from GCP..."
	@echo "Using PROJECT_ID: $(PROJECT_ID)"
	@if [ -z "$(PROJECT_ID)" ]; then \
		echo "Error: PROJECT_ID environment variable is not set"; \
		exit 1; \
	fi
	@echo "Fetching topics from GCP..."
	@mkdir -p config
	@TOPICS=$$(gcloud pubsub topics list --project="$(PROJECT_ID)" --format="value(name)"); \
	echo "Found topics: $$TOPICS"; \
	JSON_OUTPUT='{"topics": ['; \
	FIRST_TOPIC=true; \
	for TOPIC in $$TOPICS; do \
		echo "Processing topic: $$TOPIC"; \
		if [ "$$FIRST_TOPIC" = false ]; then \
			JSON_OUTPUT="$$JSON_OUTPUT,"; \
		fi; \
		FIRST_TOPIC=false; \
		TOPIC_NAME=$$(basename "$$TOPIC"); \
		echo "Topic name: $$TOPIC_NAME"; \
		JSON_OUTPUT="$$JSON_OUTPUT{\"name\": \"$$TOPIC_NAME\",\"subscriptions\": ["; \
		echo "Fetching subscriptions for topic $$TOPIC..."; \
		ACCESS_TOKEN=$$(gcloud auth print-access-token); \
		SUBSCRIPTIONS=$$(curl -s -H "Authorization: Bearer $$ACCESS_TOKEN" \
			"https://pubsub.googleapis.com/v1/projects/$(PROJECT_ID)/topics/$$TOPIC_NAME/subscriptions" | \
			jq -r '.subscriptions[]? // empty'); \
		echo "Raw subscriptions output: $$SUBSCRIPTIONS"; \
		if [ -z "$$SUBSCRIPTIONS" ]; then \
			echo "No subscriptions found for topic $$TOPIC"; \
		else \
			echo "Found subscriptions: $$SUBSCRIPTIONS"; \
			FIRST_SUB=true; \
			for SUB in $$SUBSCRIPTIONS; do \
				echo "Processing subscription: $$SUB"; \
				if [ "$$FIRST_SUB" = false ]; then \
					JSON_OUTPUT="$$JSON_OUTPUT,"; \
				fi; \
				FIRST_SUB=false; \
				SUB_NAME=$$(basename "$$SUB"); \
				echo "Subscription name: $$SUB_NAME"; \
				echo "Fetching subscription details..."; \
				SUB_DETAILS=$$(curl -s -H "Authorization: Bearer $$ACCESS_TOKEN" \
					"https://pubsub.googleapis.com/v1/projects/$(PROJECT_ID)/subscriptions/$$SUB_NAME"); \
				echo "Raw subscription details: $$SUB_DETAILS"; \
				PUSH_ENDPOINT=$$(echo "$$SUB_DETAILS" | jq -r '.pushConfig.pushEndpoint // empty'); \
				PUSH_ATTRIBUTES=$$(echo "$$SUB_DETAILS" | jq -r '.pushConfig.attributes // {}'); \
				ACK_DEADLINE=$$(echo "$$SUB_DETAILS" | jq -r '.ackDeadlineSeconds // 10'); \
				RETENTION=$$(echo "$$SUB_DETAILS" | jq -r '.messageRetentionDuration // "604800s"'); \
				echo "Push endpoint: $$PUSH_ENDPOINT"; \
				echo "Push attributes: $$PUSH_ATTRIBUTES"; \
				echo "Ack deadline: $$ACK_DEADLINE"; \
				echo "Retention: $$RETENTION"; \
				if [ -n "$$PUSH_ENDPOINT" ] && [ "$$PUSH_ENDPOINT" != "null" ] && [ "$$PUSH_ENDPOINT" != "{}" ]; then \
					SUB_TYPE="push"; \
					PUSH_CONFIG=",\"pushConfig\":{\"attributes\":$$PUSH_ATTRIBUTES}"; \
					if [ -f "config/pubsub-config.json" ]; then \
						EXISTING_SUB_JSON=$$(cat config/pubsub-config.json | jq -r --arg topic "$$TOPIC_NAME" --arg sub "$$SUB_NAME" '.topics[] | select(.name == $$topic) | .subscriptions[] | select(.name == $$sub) // empty'); \
						if [ -n "$$EXISTING_SUB_JSON" ]; then \
							PUSH_DEV=$$(echo "$$EXISTING_SUB_JSON" | jq -r '.pushEndpointDev // empty'); \
							PUSH_STAGING=$$(echo "$$EXISTING_SUB_JSON" | jq -r '.pushEndpointStaging // empty'); \
							PUSH_PROD=$$(echo "$$EXISTING_SUB_JSON" | jq -r '.pushEndpointProd // empty'); \
							ENV_ENDPOINTS=""; \
							if [ -n "$$PUSH_DEV" ] && [ "$$PUSH_DEV" != "null" ]; then \
								ENV_ENDPOINTS="$$ENV_ENDPOINTS,\"pushEndpointDev\":\"$$PUSH_DEV\""; \
							fi; \
							if [ -n "$$PUSH_STAGING" ] && [ "$$PUSH_STAGING" != "null" ]; then \
								ENV_ENDPOINTS="$$ENV_ENDPOINTS,\"pushEndpointStaging\":\"$$PUSH_STAGING\""; \
							fi; \
							if [ -n "$$PUSH_PROD" ] && [ "$$PUSH_PROD" != "null" ]; then \
								ENV_ENDPOINTS="$$ENV_ENDPOINTS,\"pushEndpointProd\":\"$$PUSH_PROD\""; \
							fi; \
							if [ -n "$$ENV_ENDPOINTS" ]; then \
								SUB_JSON="{\"name\":\"$$SUB_NAME\",\"type\":\"$$SUB_TYPE\",\"pushEndpoint\":\"$$PUSH_ENDPOINT\",\"ackDeadlineSeconds\":$$ACK_DEADLINE,\"messageRetentionDuration\":\"$$RETENTION\"$$ENV_ENDPOINTS$$PUSH_CONFIG}"; \
							else \
								SUB_JSON="{\"name\":\"$$SUB_NAME\",\"type\":\"$$SUB_TYPE\",\"pushEndpoint\":\"$$PUSH_ENDPOINT\",\"ackDeadlineSeconds\":$$ACK_DEADLINE,\"messageRetentionDuration\":\"$$RETENTION\"$$PUSH_CONFIG}"; \
							fi; \
						else \
							SUB_JSON="{\"name\":\"$$SUB_NAME\",\"type\":\"$$SUB_TYPE\",\"pushEndpoint\":\"$$PUSH_ENDPOINT\",\"ackDeadlineSeconds\":$$ACK_DEADLINE,\"messageRetentionDuration\":\"$$RETENTION\"$$PUSH_CONFIG}"; \
						fi; \
					else \
						SUB_JSON="{\"name\":\"$$SUB_NAME\",\"type\":\"$$SUB_TYPE\",\"pushEndpoint\":\"$$PUSH_ENDPOINT\",\"ackDeadlineSeconds\":$$ACK_DEADLINE,\"messageRetentionDuration\":\"$$RETENTION\"$$PUSH_CONFIG}"; \
					fi; \
				else \
					SUB_TYPE="pull"; \
					PUSH_CONFIG=""; \
					SUB_JSON="{\"name\":\"$$SUB_NAME\",\"type\":\"$$SUB_TYPE\",\"ackDeadlineSeconds\":$$ACK_DEADLINE,\"messageRetentionDuration\":\"$$RETENTION\"$$PUSH_CONFIG}"; \
				fi; \
				echo "Subscription type: $$SUB_TYPE"; \
				echo "Writing subscription to config: $$SUB_JSON"; \
				JSON_OUTPUT="$$JSON_OUTPUT$$SUB_JSON"; \
			done; \
		fi; \
		JSON_OUTPUT="$$JSON_OUTPUT]}"; \
	done; \
	JSON_OUTPUT="$$JSON_OUTPUT]}"; \
	echo "Final JSON before formatting: $$JSON_OUTPUT"; \
	echo "$$JSON_OUTPUT" | jq '.' > config/pubsub-config.json; \
	echo "Successfully synced Pub/Sub configuration from GCP to config/pubsub-config.json"

sync-to-gcp:
	@echo "Syncing configuration to GCP..."
	@if [ -z "$(PROJECT_ID)" ]; then echo "Error: PROJECT_ID environment variable is not set"; exit 1; fi
	$(call detect_environment)
	@echo "Using PROJECT_ID: $(PROJECT_ID) in $(ENV) environment"
	@if [ ! -f "config/pubsub-config.json" ]; then echo "Error: config/pubsub-config.json not found"; exit 1; fi
	
	@echo "Checking for topics to delete..."
	@CONFIG_TOPICS=$$(jq -r '.topics[].name' config/pubsub-config.json | sort | tr '\n' ' '); \
	GCP_TOPICS=$$(gcloud pubsub topics list --project="$(PROJECT_ID)" --format="value(name)" | xargs -I{} basename {} | sort); \
	for topic in $$GCP_TOPICS; do \
		if ! echo "$$CONFIG_TOPICS" | grep -w "$$topic" > /dev/null; then \
			echo "Deleting topic not in config: $$topic"; \
			gcloud pubsub topics delete "$$topic" --project="$(PROJECT_ID)" --quiet; \
		fi; \
	done
	
	@echo "Checking for subscriptions to delete..."
	@CONFIG_SUBS=''; \
	for topic in $$(jq -r '.topics[].name' config/pubsub-config.json); do \
		for sub in $$(jq -r --arg t "$$topic" '.topics[] | select(.name == $$t) | .subscriptions[].name' config/pubsub-config.json); do \
			CONFIG_SUBS="$$CONFIG_SUBS $$sub"; \
		done; \
	done; \
	echo "Subscriptions in config: $$CONFIG_SUBS"; \
	GCP_SUBS=$$(gcloud pubsub subscriptions list --project="$(PROJECT_ID)" --format="value(name)" | xargs -I{} basename {}); \
	for sub in $$GCP_SUBS; do \
		if ! echo "$$CONFIG_SUBS" | grep -w "$$sub" > /dev/null; then \
			echo "Deleting subscription not in config: $$sub"; \
			gcloud pubsub subscriptions delete "$$sub" --project="$(PROJECT_ID)" --quiet; \
			continue; \
		fi; \
		SUB_TOPIC=$$(gcloud pubsub subscriptions describe "$$sub" --project="$(PROJECT_ID)" --format="value(topic)" 2>/dev/null || echo ""); \
		if [ -z "$$SUB_TOPIC" ] || echo "$$SUB_TOPIC" | grep -q "_deleted-topic_"; then \
			echo "Deleting subscription with deleted topic: $$sub"; \
			gcloud pubsub subscriptions delete "$$sub" --project="$(PROJECT_ID)" --quiet; \
		fi; \
	done
	
	@echo "Creating topics from config..."
	@for topic in $$(jq -r '.topics[].name' config/pubsub-config.json); do \
		echo "Creating topic: $$topic"; \
		gcloud pubsub topics create "$$topic" --project="$(PROJECT_ID)" 2>/dev/null || true; \
	done
	@echo "Creating/updating subscriptions..."
	@for topic in $$(jq -r '.topics[].name' config/pubsub-config.json); do \
		echo "Processing subscriptions for topic: $$topic"; \
		for sub in $$(jq -r --arg t "$$topic" '.topics[] | select(.name == $$t) | .subscriptions[].name' config/pubsub-config.json); do \
			sub_type=$$(jq -r --arg t "$$topic" --arg s "$$sub" '.topics[] | select(.name == $$t) | .subscriptions[] | select(.name == $$s) | .type // "pull"' config/pubsub-config.json); \
			echo "  Processing subscription: $$sub (type: $$sub_type)"; \
			ack_deadline=$$(jq -r --arg t "$$topic" --arg s "$$sub" '.topics[] | select(.name == $$t) | .subscriptions[] | select(.name == $$s) | .ackDeadlineSeconds // 10' config/pubsub-config.json); \
			retention=$$(jq -r --arg t "$$topic" --arg s "$$sub" '.topics[] | select(.name == $$t) | .subscriptions[] | select(.name == $$s) | .messageRetentionDuration // "604800s"' config/pubsub-config.json); \
			SUB_EXISTS=false; \
			SUB_TOPIC=""; \
			if gcloud pubsub subscriptions describe "$$sub" --project="$(PROJECT_ID)" > /dev/null 2>&1; then \
				SUB_EXISTS=true; \
				SUB_TOPIC=$$(gcloud pubsub subscriptions describe "$$sub" --project="$(PROJECT_ID)" --format="value(topic)"); \
				if [ "$$SUB_TOPIC" != "projects/$(PROJECT_ID)/topics/$$topic" ]; then \
					echo "    Subscription exists but points to wrong topic ($$SUB_TOPIC), recreating..."; \
					gcloud pubsub subscriptions delete "$$sub" --project="$(PROJECT_ID)" --quiet; \
					SUB_EXISTS=false; \
				fi; \
			fi; \
			if [ "$$sub_type" = "push" ]; then \
				if [ "$(ENV)" = "prod" ]; then \
					push_endpoint=$$(jq -r --arg t "$$topic" --arg s "$$sub" '.topics[] | select(.name == $$t) | .subscriptions[] | select(.name == $$s) | .pushEndpointProd // ""' config/pubsub-config.json); \
				elif [ "$(ENV)" = "staging" ]; then \
					push_endpoint=$$(jq -r --arg t "$$topic" --arg s "$$sub" '.topics[] | select(.name == $$t) | .subscriptions[] | select(.name == $$s) | .pushEndpointStaging // ""' config/pubsub-config.json); \
				else \
					push_endpoint=$$(jq -r --arg t "$$topic" --arg s "$$sub" '.topics[] | select(.name == $$t) | .subscriptions[] | select(.name == $$s) | .pushEndpointDev // ""' config/pubsub-config.json); \
					if [ -z "$$push_endpoint" ] || [ "$$push_endpoint" = "null" ]; then \
						push_endpoint=$$(jq -r --arg t "$$topic" --arg s "$$sub" '.topics[] | select(.name == $$t) | .subscriptions[] | select(.name == $$s) | .pushEndpoint // ""' config/pubsub-config.json); \
					fi; \
				fi; \
				echo "    Recreating push subscription..."; \
				gcloud pubsub subscriptions delete "$$sub" --project="$(PROJECT_ID)" --quiet 2>/dev/null || true; \
				if [ -n "$$push_endpoint" ]; then \
					if echo "$$push_endpoint" | grep -q "host.docker.internal"; then \
						url_path=$$(echo "$$push_endpoint" | sed -n 's|.*/||p'); \
						if [ -z "$$url_path" ]; then url_path="pubsub-placeholder"; fi; \
						if [ "$(ENV)" = "prod" ]; then \
							actual_endpoint="$(PROD_BASE_URL)/$$url_path"; \
						elif [ "$(ENV)" = "staging" ]; then \
							actual_endpoint="$(STAGING_BASE_URL)/$$url_path"; \
						else \
							actual_endpoint="$(DEV_BASE_URL)/$$url_path"; \
						fi; \
						echo "    Creating push subscription with endpoint: $$actual_endpoint"; \
						gcloud pubsub subscriptions create "$$sub" --topic="$$topic" --project="$(PROJECT_ID)" \
							--push-endpoint="$$actual_endpoint" \
							--ack-deadline=$$ack_deadline --message-retention-duration=$$retention; \
					else \
						echo "    Creating push subscription with explicit endpoint: $$push_endpoint"; \
						gcloud pubsub subscriptions create "$$sub" --topic="$$topic" --project="$(PROJECT_ID)" \
							--push-endpoint="$$push_endpoint" \
							--ack-deadline=$$ack_deadline --message-retention-duration=$$retention; \
					fi; \
				else \
					echo "    WARNING: No push endpoint defined for push subscription $$sub, creating as pull"; \
					gcloud pubsub subscriptions create "$$sub" --topic="$$topic" --project="$(PROJECT_ID)" \
						--ack-deadline=$$ack_deadline --message-retention-duration=$$retention; \
				fi; \
			else \
				if [ "$$SUB_EXISTS" = false ]; then \
					echo "    Creating pull subscription"; \
					gcloud pubsub subscriptions create "$$sub" --topic="$$topic" --project="$(PROJECT_ID)" \
						--ack-deadline=$$ack_deadline --message-retention-duration=$$retention; \
				fi; \
			fi; \
		done; \
	done
	@echo "Successfully synced configuration to GCP"

clean:
	pkill -f "bun.*src/index.ts" || true
	pkill -f "bun.*service1/src/index.ts" || true
	pkill -f "bun.*service2/src/index.ts" || true
	docker stop pubsub-emulator || true
	docker rm pubsub-emulator || true 