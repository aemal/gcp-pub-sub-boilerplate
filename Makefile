.PHONY: dev clean check-docker start-emulator sync-from-gcp sync-to-gcp

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

dev: check-docker sync-from-gcp start-emulator
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
	@TOPICS=$$(gcloud pubsub topics list --project="$(PROJECT_ID)" --format="value(name)"); \
	echo "Found topics: $$TOPICS"; \
	echo '{"topics": [' > config/pubsub-config.json.tmp; \
	FIRST_TOPIC=true; \
	for TOPIC in $$TOPICS; do \
		echo "Processing topic: $$TOPIC"; \
		if [ "$$FIRST_TOPIC" = false ]; then \
			echo "," >> config/pubsub-config.json.tmp; \
		fi; \
		FIRST_TOPIC=false; \
		TOPIC_NAME=$$(basename "$$TOPIC"); \
		echo "Topic name: $$TOPIC_NAME"; \
		echo "    {\"name\": \"$$TOPIC_NAME\",\"subscriptions\": [" >> config/pubsub-config.json.tmp; \
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
					echo "," >> config/pubsub-config.json.tmp; \
				fi; \
				FIRST_SUB=false; \
				SUB_NAME=$$(basename "$$SUB"); \
				echo "Subscription name: $$SUB_NAME"; \
				echo "Fetching subscription details..."; \
				SUB_DETAILS=$$(curl -s -H "Authorization: Bearer $$ACCESS_TOKEN" \
					"https://pubsub.googleapis.com/v1/projects/$(PROJECT_ID)/subscriptions/$$SUB_NAME"); \
				echo "Raw subscription details: $$SUB_DETAILS"; \
				PUSH_ENDPOINT=$$(echo "$$SUB_DETAILS" | jq -r '.pushConfig.pushEndpoint // empty'); \
				PUSH_ATTRIBUTES=$$(echo "$$SUB_DETAILS" | jq -r '.pushConfig.attributes // empty'); \
				ACK_DEADLINE=$$(echo "$$SUB_DETAILS" | jq -r '.ackDeadlineSeconds // 10'); \
				RETENTION=$$(echo "$$SUB_DETAILS" | jq -r '.messageRetentionDuration // "604800s"'); \
				echo "Push endpoint: $$PUSH_ENDPOINT"; \
				echo "Push attributes: $$PUSH_ATTRIBUTES"; \
				echo "Ack deadline: $$ACK_DEADLINE"; \
				echo "Retention: $$RETENTION"; \
				if [ -n "$$PUSH_ENDPOINT" ] && [ "$$PUSH_ENDPOINT" != "null" ] && [ "$$PUSH_ENDPOINT" != "{}" ]; then \
					SUB_TYPE="push"; \
					PUSH_CONFIG=",\"pushConfig\":{\"attributes\":$$PUSH_ATTRIBUTES}"; \
				else \
					SUB_TYPE="pull"; \
					PUSH_CONFIG=""; \
				fi; \
				echo "Subscription type: $$SUB_TYPE"; \
				echo "Writing subscription to config: {\"name\":\"$$SUB_NAME\",\"type\":\"$$SUB_TYPE\",\"pushEndpoint\":\"$$PUSH_ENDPOINT\",\"ackDeadlineSeconds\":$$ACK_DEADLINE,\"messageRetentionDuration\":\"$$RETENTION\"$$PUSH_CONFIG}"; \
				echo "        {\"name\":\"$$SUB_NAME\",\"type\":\"$$SUB_TYPE\",\"pushEndpoint\":\"$$PUSH_ENDPOINT\",\"ackDeadlineSeconds\":$$ACK_DEADLINE,\"messageRetentionDuration\":\"$$RETENTION\"$$PUSH_CONFIG}" >> config/pubsub-config.json.tmp; \
			done; \
		fi; \
		echo "      ]}" >> config/pubsub-config.json.tmp; \
	done; \
	echo "  ]}" >> config/pubsub-config.json.tmp; \
	mv config/pubsub-config.json.tmp config/pubsub-config.json; \
	echo "Successfully synced Pub/Sub configuration from GCP to config/pubsub-config.json"

sync-to-gcp:
	@echo "Syncing configuration to GCP..."
	@echo "Using PROJECT_ID: $(PROJECT_ID)"
	@if [ -z "$(PROJECT_ID)" ]; then \
		echo "Error: PROJECT_ID environment variable is not set"; \
		exit 1; \
	fi
	@if [ ! -f "config/pubsub-config.json" ]; then \
		echo "Error: config/pubsub-config.json not found"; \
		exit 1; \
	fi
	@CONFIG=$$(cat config/pubsub-config.json); \
	GCP_TOPICS=$$(gcloud pubsub topics list --project="$(PROJECT_ID)" --format="value(name)"); \
	echo "$$CONFIG" | jq -r '.topics[] | .name' | while read -r TOPIC_NAME; do \
		TOPIC_PATH="projects/$(PROJECT_ID)/topics/$$TOPIC_NAME"; \
		if ! echo "$$GCP_TOPICS" | grep -q "$$TOPIC_PATH"; then \
			echo "Creating topic: $$TOPIC_NAME"; \
			gcloud pubsub topics create "$$TOPIC_NAME" --project="$(PROJECT_ID)"; \
		fi; \
		GCP_SUBS=$$(gcloud pubsub topics list-subscriptions "$$TOPIC_PATH" --project="$(PROJECT_ID)" --format="value(name)"); \
		echo "$$CONFIG" | jq -r --arg topic "$$TOPIC_NAME" '.topics[] | select(.name == $$topic) | .subscriptions[] | .name' | while read -r SUB_NAME; do \
			SUB_PATH="projects/$(PROJECT_ID)/subscriptions/$$SUB_NAME"; \
			if ! echo "$$GCP_SUBS" | grep -q "$$SUB_PATH"; then \
				echo "Creating subscription: $$SUB_NAME"; \
				SUB_CONFIG=$$(echo "$$CONFIG" | jq -r --arg topic "$$TOPIC_NAME" --arg sub "$$SUB_NAME" '.topics[] | select(.name == $$topic) | .subscriptions[] | select(.name == $$sub)'); \
				CMD="gcloud pubsub subscriptions create $$SUB_NAME --topic=$$TOPIC_NAME --project=$(PROJECT_ID)"; \
				PUSH_ENDPOINT=$$(echo "$$SUB_CONFIG" | jq -r '.pushEndpoint // empty'); \
				if [ -n "$$PUSH_ENDPOINT" ] && [ "$$PUSH_ENDPOINT" != "null" ]; then \
					CMD="$$CMD --push-endpoint=$$PUSH_ENDPOINT"; \
					PUSH_ATTRS=$$(echo "$$SUB_CONFIG" | jq -r '.pushConfig.attributes // empty'); \
					if [ "$$PUSH_ATTRS" != "null" ]; then \
						CMD="$$CMD --push-attributes=$$PUSH_ATTRS"; \
					fi; \
				fi; \
				ACK_DEADLINE=$$(echo "$$SUB_CONFIG" | jq -r '.ackDeadlineSeconds'); \
				RETENTION=$$(echo "$$SUB_CONFIG" | jq -r '.messageRetentionDuration'); \
				CMD="$$CMD --ack-deadline=$$ACK_DEADLINE --message-retention-duration=$$RETENTION"; \
				eval "$$CMD" || true; \
			else \
				echo "Subscription $$SUB_NAME already exists, skipping creation"; \
			fi; \
		done; \
	done; \
	echo "$$GCP_TOPICS" | while read -r GCP_TOPIC; do \
		TOPIC_NAME=$$(basename "$$GCP_TOPIC"); \
		if ! echo "$$CONFIG" | jq -r '.topics[] | .name' | grep -q "^$$TOPIC_NAME$$"; then \
			echo "Deleting topic: $$TOPIC_NAME"; \
			gcloud pubsub topics delete "$$TOPIC_NAME" --project="$(PROJECT_ID)"; \
		fi; \
	done
	@echo "Successfully synced local configuration to GCP Pub/Sub"

clean:
	pkill -f "bun.*src/index.ts" || true
	pkill -f "bun.*service1/src/index.ts" || true
	pkill -f "bun.*service2/src/index.ts" || true
	docker stop pubsub-emulator || true
	docker rm pubsub-emulator || true 