# GCP PubSub Development Environment & A Minimalistic Boilerplate

This repository is actually a monorepo that uses Git submodules to manage three separate components:

1. `service1` (Publisher service) - A Git submodule
2. `service2` (Subscriber service) - A Git submodule
3. `pubsub-emulator-ui` (Web UI for monitoring) - A Git submodule

The main repository (gcp-pub-sub-boilerplate) serves as a development environment and orchestration layer that brings these components together. 

## Initial Repository Setup

```bash
# Initialize the repository
git init
git remote add origin https://github.com/aemal/gcp-pub-sub-boilerplate.git
git branch -M main

# Add the submodules
git submodule add https://github.com/aemal/gcp-pub-sub-boilerplate-service1.git service1
git submodule add https://github.com/aemal/gcp-pub-sub-boilerplate-service2.git service2
git submodule add https://github.com/aemal/gcp-pub-sub-boilerplate-pubsub-emulator-ui.git pubsub-emulator-ui

# Commit and push
git add .gitmodules service1 service2 pubsub-emulator-ui
git commit -m "Add submodules for services and UI"
git push --set-upstream origin main
```

## Cloning the Repository

For new users who want to clone the repository:

```bash
# Clone with all submodules (recommended)
git clone --recursive https://github.com/aemal/gcp-pub-sub-boilerplate.git

# OR clone and then initialize submodules separately
git clone https://github.com/aemal/gcp-pub-sub-boilerplate.git
cd gcp-pub-sub-boilerplate
git submodule update --init --recursive
```

This repository consists of three main components, managed as Git submodules:
- `service1`: Publisher service (Node.js/Fastify)
- `service2`: Subscriber service (Node.js/Fastify)
- `pubsub-emulator-ui`: Web UI for monitoring Pub/Sub operations

## Purpose

This project serves as a complete, production-ready development environment for Google Cloud Pub/Sub applications. It consolidates various code snippets, configurations, and boilerplates into a minimalistic, understandable format that developers can use as a foundation for their Pub/Sub implementations.

### Key Features

- **Local Development**: Complete local development setup using Pub/Sub emulator
- **Service Architecture**: 
  - `service1`: Publisher service (Node.js/Fastify)
  - `service2`: Subscriber service with real-time updates (Node.js/Fastify)
  - `pubsub-emulator-ui`: Web interface for monitoring Pub/Sub operations
- **Developer Tools**:
  - Local Pub/Sub emulator configuration
  - Development scripts for quick setup
  - CORS proxy for UI development
  - Docker support for containerization
- **Dynamic Configuration**:
  - JSON-based configuration for topics and subscriptions
  - Support for both pull and push subscriptions
  - Easy to extend and modify

### Why This Project?

1. **Complete Solution**: Instead of piecing together different components, this project provides a fully functional setup that works out of the box
2. **Best Practices**: Implements Google Cloud Pub/Sub best practices for both local development and production
3. **Modern Stack**: Uses modern technologies like Bun runtime, Fastify, and Angular
4. **Developer Experience**: Focuses on providing a smooth development experience with:
   - Clear documentation
   - Easy setup process
   - Development scripts
   - Real-time message monitoring
   - Web-based UI for topic/subscription management

This repository contains a complete development environment for working with Google Cloud Pub/Sub, including:

- Local Pub/Sub emulator
- Publisher service (service1)
- Subscriber service (service2)
- Web UI for Pub/Sub emulator (pubsub-emulator-ui)
- Development scripts

**Author**: [Aemal Sayer](https://AemalSayer.com)

## Prerequisites

- Node.js 16+
- Bun runtime
- Google Cloud SDK (for Pub/Sub emulator)
- Docker (optional, for containerization)
- local-cors-proxy (for UI development)
- jq (for JSON processing)

## Local Development

### Starting the Development Environment

```bash
# Make the script executable
chmod +x scripts/dev.sh

# Start the development environment
./scripts/dev.sh
```

This will:
1. Start the Pub/Sub emulator
2. Create topics and subscriptions from the configuration
3. Start the publisher service (service1)
4. Start the subscriber service (service2)
5. Start the Pub/Sub emulator UI

### Testing the Local Environment

1. **Using Postman**:
   - Send a POST request to `http://localhost:3000/publish` with body:
     ```json
     {
       "message": "Hello World",
       "topicName": "notifications"
     }
     ```
   - Check the console of service2 to see the received message

2. **Using the Pub/Sub Emulator UI**:
   - Open `http://localhost:4200` in your browser
   - Navigate to the "Publish" tab
   - Select the topic "notifications"
   - Enter a message and click "Publish"
   - Check the console of service2 to see the received message

## Production Deployment

### Setting Up GCP Project

1. Install Google Cloud SDK if you haven't already:
   ```bash
   # macOS (using Homebrew)
   brew install google-cloud-sdk

   # Other platforms
   # Visit https://cloud.google.com/sdk/docs/install
   ```

2. Authenticate with Google Cloud:
   ```bash
   gcloud auth login
   ```

3. List your projects and note the project ID:
   ```bash
   gcloud projects list
   ```

4. Set your project ID:
   ```bash
   # Replace YOUR_PROJECT_ID with your actual project ID
   gcloud config set project YOUR_PROJECT_ID
   ```

5. Enable required APIs:
   ```bash
   gcloud services enable \
     run.googleapis.com \
     pubsub.googleapis.com \
     containerregistry.googleapis.com
   ```

### Setting Up Workload Identity Federation

```bash
# Create a Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create a Workload Identity Provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-condition="attribute.repository=='aemal/gcp-pub-sub-boilerplate'"

# Create service account
gcloud iam service-accounts create "github-actions" \
  --display-name="GitHub Actions service account"

# Grant necessary roles
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:github-actions@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:github-actions@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/pubsub.admin"
```

### Deploying to GCP

1. Add the Workload Identity Provider resource name to your GitHub repository secrets:
   - `WIF_PROVIDER`: The Workload Identity Provider resource name (format: `projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider`)
   
   You can get this value by running:
   ```bash
   gcloud iam workload-identity-pools providers describe "github-provider" \
     --location="global" \
     --workload-identity-pool="github-pool" \
     --format="value(name)"
   ```

2. Push your code to GitHub:
   ```bash
   git add .
   git commit -m "Update configuration and deployment scripts"
   git push origin main
   ```

3. The GitHub Actions workflows will automatically:
   - Deploy the Pub/Sub infrastructure
   - Deploy service1 to Cloud Run
   - Deploy service2 to Cloud Run

### Testing the Production Environment

1. **Using Postman**:
   - Send a POST request to the Cloud Run URL of service1 (e.g., `https://pubsub-publisher-xxxxx-uc.a.run.app/publish`) with body:
     ```json
     {
       "message": "Hello World",
       "topicName": "notifications"
     }
     ```
   - Check the Cloud Run logs of service2 to see the received message

## Pub/Sub Configuration

The Pub/Sub configuration is defined in `config/pubsub-config.json`. This file contains:

- Topics
- Subscriptions (both pull and push)
- Subscription settings (ackDeadlineSeconds, messageRetentionDuration)

Example configuration:
```json
{
  "topics": [
    {
      "name": "my-topic",
      "subscriptions": [
        {
          "name": "my-subscription",
          "type": "pull",
          "ackDeadlineSeconds": 10,
          "messageRetentionDuration": "604800s"
        }
      ]
    },
    {
      "name": "notifications",
      "subscriptions": [
        {
          "name": "email-notifications",
          "type": "push",
          "pushEndpoint": "https://email-service-xxxxx-uc.a.run.app/notifications",
          "ackDeadlineSeconds": 30,
          "messageRetentionDuration": "2592000s"
        }
      ]
    }
  ]
}
```

## Environment Variables

The services can be configured using environment variables:

```bash
# Required for production, optional for development
PUBSUB_PROJECT_ID=your-project-id    # Your GCP project ID
PUBSUB_EMULATOR_HOST=localhost:8790  # Emulator host:port

# Optional
PUBSUB_TOPIC_NAME=my-topic           # Default topic name
PUBSUB_SUBSCRIPTION_NAME=my-subscription  # Default subscription name
```

## Common Issues

1. **404 Not Found for Topics**: Make sure the CORS proxy is running with the correct parameters
2. **Connection Refused**: Ensure the Pub/Sub emulator is running (check port 8790)
3. **UI Not Updating**: Verify the WebSocket connection in the browser console
4. **Project ID Issues**: 
   - Verify your project ID in all configuration files
   - Ensure you have the correct permissions in GCP
   - Check if the project ID is properly set in gcloud config
5. **Push Subscription Issues**:
   - Ensure the push endpoint is accessible from GCP
   - Check that the service account has the necessary permissions
   - Verify that the endpoint returns a 2xx status code

## Repository Structure

This project uses Git submodules to manage its components. The structure is:

```
pubsub/
├── config/                  # Pub/Sub configuration
├── scripts/                 # Development and deployment scripts
├── service1/                # Publisher service
├── service2/                # Subscriber service
└── pubsub-emulator-ui/      # Web UI for monitoring
```

## Updating Submodules

To update all submodules to their latest versions:
```bash
git submodule update --remote --merge
```

[... rest of the content remains the same ...] 