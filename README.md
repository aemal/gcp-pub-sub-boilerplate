# GCP PubSub Development Environment & A Minimalistic Boilerplate

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

## GCP Project Setup

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

5. Replace the default project ID in the following files:
   ```bash
   # Current default: gcp-pubsub-456020
   
   # service1/src/index.ts
   const projectId = process.env.PUBSUB_PROJECT_ID || 'YOUR_PROJECT_ID';

   # service2/src/index.ts
   const projectId = process.env.PUBSUB_PROJECT_ID || 'YOUR_PROJECT_ID';

   # pubsub-emulator-ui/webapp/src/environments/environment.ts
   export const environment = {
     production: false,
     pubsubEmulator: {
       host: 'http://localhost:8010',
       projectId: 'YOUR_PROJECT_ID'
     }
   };

   # pubsub-emulator-ui/webapp/src/environments/environment.prod.ts
   export const environment = {
     production: true,
     pubsubEmulator: {
       host: 'http://localhost:8010',
       projectId: 'YOUR_PROJECT_ID'
     }
   };
   ```

   You can use this command to replace all occurrences:
   ```bash
   # macOS/Linux
   find . -type f -exec sed -i '' 's/gcp-pubsub-456020/YOUR_PROJECT_ID/g' {} +
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

## Repository Structure

This project uses Git submodules to manage its components. The structure is:

```
pubsub/
├── service1/                 # Publisher service
├── service2/                # Subscriber service
└── pubsub-emulator-ui/     # Web UI for monitoring
```

## Updating Submodules

To update all submodules to their latest versions:
```bash
git submodule update --remote --merge
```

[... rest of the content remains the same ...] 