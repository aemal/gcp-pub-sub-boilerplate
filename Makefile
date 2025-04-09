.PHONY: dev clean check-docker start-emulator

dev: check-docker start-emulator
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

clean:
	pkill -f "bun.*src/index.ts" || true
	pkill -f "bun.*service1/src/index.ts" || true
	pkill -f "bun.*service2/src/index.ts" || true
	docker stop pubsub-emulator || true
	docker rm pubsub-emulator || true 