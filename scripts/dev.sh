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

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install it first."
    echo "macOS: brew install jq"
    echo "Ubuntu/Debian: sudo apt-get install jq"
    exit 1
fi

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

# Read the configuration file
CONFIG_FILE="$ROOT_DIR/config/pubsub-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Create topics and subscriptions
echo "Creating topics and subscriptions..."
jq -c '.topics[]' "$CONFIG_FILE" | while read -r topic; do
    topic_name=$(echo "$topic" | jq -r '.name')
    
    echo "Creating topic: $topic_name"
    curl -X PUT "http://localhost:8790/v1/projects/$PUBSUB_PROJECT_ID/topics/$topic_name" || true
    
    # Create subscriptions for this topic
    echo "$topic" | jq -c '.subscriptions[]' | while read -r subscription; do
        sub_name=$(echo "$subscription" | jq -r '.name')
        sub_type=$(echo "$subscription" | jq -r '.type // "pull"')
        ack_deadline=$(echo "$subscription" | jq -r '.ackDeadlineSeconds // 10')
        retention=$(echo "$subscription" | jq -r '.messageRetentionDuration // "604800s"')
        
        echo "Creating subscription: $sub_name for topic: $topic_name (type: $sub_type)"
        
        if [ "$sub_type" = "push" ]; then
            push_endpoint=$(echo "$subscription" | jq -r '.pushEndpoint')
            if [ -z "$push_endpoint" ]; then
                echo "Error: pushEndpoint is required for push subscriptions"
                continue
            fi
            
            # For local development, we'll use service2's endpoint
            local_endpoint="http://localhost:3001/notifications"
            
            echo "Creating push subscription with local endpoint: $local_endpoint"
            curl -X PUT "http://localhost:8790/v1/projects/$PUBSUB_PROJECT_ID/subscriptions/$sub_name" \
                -H "Content-Type: application/json" \
                -d "{
                    \"topic\": \"projects/$PUBSUB_PROJECT_ID/topics/$topic_name\",
                    \"ackDeadlineSeconds\": $ack_deadline,
                    \"messageRetentionDuration\": \"$retention\",
                    \"pushConfig\": {
                        \"pushEndpoint\": \"$local_endpoint\"
                    }
                }" || true
        else
            # Create pull subscription
            curl -X PUT "http://localhost:8790/v1/projects/$PUBSUB_PROJECT_ID/subscriptions/$sub_name" \
                -H "Content-Type: application/json" \
                -d "{
                    \"topic\": \"projects/$PUBSUB_PROJECT_ID/topics/$topic_name\",
                    \"ackDeadlineSeconds\": $ack_deadline,
                    \"messageRetentionDuration\": \"$retention\"
                }" || true
        fi
    done
done

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
echo ""
echo "To test the system:"
echo "1. Use Postman to send a POST request to http://localhost:3000/publish with body: {\"message\": \"Hello World\", \"topicName\": \"notifications\"}"
echo "2. Check the console of service2 to see the received message"

# Wait for any process to exit
wait

# Cleanup will be called automatically on exit 