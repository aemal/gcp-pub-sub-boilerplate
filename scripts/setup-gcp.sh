#!/bin/bash

# Exit on error
set -e

# Load environment variables
source .env

# Check if required environment variables are set
if [ -z "$PROJECT_ID" ]; then
    echo "Error: PROJECT_ID environment variable is not set"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install it first."
    echo "macOS: brew install jq"
    echo "Ubuntu/Debian: sudo apt-get install jq"
    exit 1
fi

echo "Setting up GCP Pub/Sub infrastructure for project: $PROJECT_ID"

# Read the configuration file
CONFIG_FILE="config/pubsub-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Get the Cloud Run service accounts
PUBLISHER_SA="${PROJECT_ID}.appspot.com"
SUBSCRIBER_SA="${PROJECT_ID}.appspot.com"

# Process each topic and its subscriptions
jq -c '.topics[]' "$CONFIG_FILE" | while read -r topic; do
    topic_name=$(echo "$topic" | jq -r '.name')
    
    echo "Creating topic: $topic_name"
    gcloud pubsub topics create "$topic_name" --project="$PROJECT_ID" || true
    
    # Grant Publisher role to the publisher service
    gcloud pubsub topics add-iam-policy-binding "$topic_name" \
        --member="serviceAccount:${PUBLISHER_SA}" \
        --role="roles/pubsub.publisher" \
        --project="$PROJECT_ID"
    
    # Process subscriptions for this topic
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
            
            # Create push subscription
            gcloud pubsub subscriptions create "$sub_name" \
                --topic="$topic_name" \
                --push-endpoint="$push_endpoint" \
                --ack-deadline="$ack_deadline" \
                --message-retention-duration="$retention" \
                --project="$PROJECT_ID" || true
                
            # Add push config attributes if specified
            push_config=$(echo "$subscription" | jq -r '.pushConfig // empty')
            if [ ! -z "$push_config" ]; then
                gcloud pubsub subscriptions modify-push-config "$sub_name" \
                    --push-endpoint="$push_endpoint" \
                    --push-auth-service-account="${SUBSCRIBER_SA}" \
                    --project="$PROJECT_ID"
            fi
        else
            # Create pull subscription
            gcloud pubsub subscriptions create "$sub_name" \
                --topic="$topic_name" \
                --ack-deadline="$ack_deadline" \
                --message-retention-duration="$retention" \
                --project="$PROJECT_ID" || true
        fi
        
        # Grant Subscriber role to the subscriber service
        gcloud pubsub subscriptions add-iam-policy-binding "$sub_name" \
            --member="serviceAccount:${SUBSCRIBER_SA}" \
            --role="roles/pubsub.subscriber" \
            --project="$PROJECT_ID"
    done
done

echo "GCP Pub/Sub infrastructure setup complete!" 