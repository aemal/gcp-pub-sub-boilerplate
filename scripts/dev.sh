#!/bin/bash

# Function to cleanup processes
cleanup() {
    echo "Cleaning up processes..."
    pkill -f "local-cors-proxy" || true
    pkill -f "bun run" || true
    pkill -f "pubsub-emulator" || true
    pkill -f "npm start" || true
    
    # Wait a moment to ensure ports are freed
    sleep 2
}

# Run cleanup before starting to ensure clean slate
cleanup

# Cleanup on script exit
trap cleanup EXIT

# Store the root directory
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "Working from directory: $ROOT_DIR"

# Start Pub/Sub emulator
echo "Starting Pub/Sub emulator..."
gcloud beta emulators pubsub start --project=gcp-pubsub-456020 --host-port=localhost:8790 &
sleep 5  # Wait for emulator to start

# Set environment variables
export PUBSUB_EMULATOR_HOST=localhost:8790
export PUBSUB_PROJECT_ID=${PUBSUB_PROJECT_ID:-gcp-pubsub-456020}

# Create topic and subscription
echo "Creating topic and subscription..."
curl -X PUT "http://localhost:8790/v1/projects/$PUBSUB_PROJECT_ID/topics/my-topic" || true
curl -X PUT "http://localhost:8790/v1/projects/$PUBSUB_PROJECT_ID/subscriptions/my-subscription" \
    -H "Content-Type: application/json" \
    -d "{\"topic\": \"projects/$PUBSUB_PROJECT_ID/topics/my-topic\"}" || true

# Start CORS proxy for UI
echo "Starting CORS proxy..."
lcp --proxyUrl http://localhost:8790 --proxyPartial 'proxy' &
sleep 2

# Start services
echo "Starting service1..."
cd "$ROOT_DIR/service1" && bun install && bun run start &

echo "Starting service2..."
cd "$ROOT_DIR/service2" && bun install && bun run start &

echo "Starting UI..."
cd "$ROOT_DIR/pubsub-emulator-ui/webapp" && npm install && npm start &

echo "All services started! Use Ctrl+C to stop all services."
echo "Publisher service: http://localhost:3000"
echo "Subscriber service: http://localhost:3001"
echo "UI: http://localhost:4200"

# Wait for any process to exit
wait

# Cleanup will be called automatically on exit 