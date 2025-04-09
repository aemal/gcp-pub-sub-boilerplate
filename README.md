# Pub/Sub Emulator UI & Sync Project

This project provides a local development environment for Google Cloud Pub/Sub using the official emulator and includes:

*   A UI (`pubsub-emulator-ui`) to visualize topics and subscriptions in the **emulator**.
*   A main service (`src/index.ts`) that initializes the emulator based on a local configuration file and provides a basic API.
*   Example services (`service1`, `service2`) that can receive push notifications.
*   Makefile targets to manage the environment and synchronize configurations with Google Cloud Platform (GCP).

## Setup

1.  **Prerequisites:**
    *   Docker & Docker Compose
    *   Node.js & Bun (`npm install -g bun`)
    *   Google Cloud SDK (`gcloud`)
    *   `jq` (JSON processor)
2.  **Environment Variables:** Create a `.env` file in the root directory with your GCP Project ID:
    ```env
    PROJECT_ID=your-gcp-project-id
    # PUBSUB_EMULATOR_HOST=http://localhost:8085 (Defaults to this if not set)
    ```
3.  **Install Dependencies:**
    ```bash
    bun install
    cd service1 && bun install
    cd service2 && bun install
    ```

## Running the Development Environment

```bash
make dev
```

This command performs the following steps:

1.  **`sync-from-gcp`**: Fetches the current topics and subscriptions from your configured GCP project (`PROJECT_ID`) and updates `config/pubsub-config.json`.
2.  Starts the Google Cloud Pub/Sub emulator in a Docker container.
3.  Waits for the emulator to be ready.
4.  Installs dependencies for all services.
5.  Starts the main Pub/Sub service (`src/index.ts`) and the example services (`service1`, `service2`) using `bun --watch` for hot-reloading.

The main service initializes topics and subscriptions within the **emulator** based on the contents of `config/pubsub-config.json`.

**Accessing Services:**

*   Pub/Sub Emulator API: `http://localhost:8085`
*   Pub/Sub Emulator UI: `http://localhost:9095` (Connects to `http://localhost:8085`)
*   Main Sync Service: `http://localhost:3000`
*   Example Service 1: `http://localhost:3001`
*   Example Service 2: `http://localhost:3002`

## Synchronization with GCP

This setup allows for two-way synchronization between your local configuration (`config/pubsub-config.json`) and your actual GCP Pub/Sub resources.

### Syncing from GCP to Local (`sync-from-gcp`)

This is run automatically as part of `make dev`. It fetches the current state of topics and subscriptions from GCP and overwrites `config/pubsub-config.json`.

*   **Command:** `make sync-from-gcp`
*   **Action:** GCP State --> `config/pubsub-config.json`

### Syncing from Local to GCP (`sync-to-gcp`)

Use this command when you have made changes locally (e.g., added a new topic or subscription to `config/pubsub-config.json`) and want to push those changes to GCP.

*   **Command:** `make sync-to-gcp`
*   **Action:** `config/pubsub-config.json` --> GCP State
*   **Workflow for Adding New Resources:**
    1.  Stop the development environment (`Ctrl+C` if `make dev` is running).
    2.  Manually edit `config/pubsub-config.json` to add/modify topics or subscriptions.
    3.  Run `make sync-to-gcp`.
    4.  Restart the development environment with `make dev` (which will first run `sync-from-gcp` to confirm the state).

**Note:** The `sync-to-gcp` command currently only *creates* topics and subscriptions in GCP if they exist locally but not remotely. It does *not* delete resources from GCP that are removed from the local config file, to prevent accidental deletion.

## Cleaning Up

```bash
make clean
```

This command stops and removes the Docker container for the Pub/Sub emulator.

## Prerequisites

- Docker
- Bun (JavaScript runtime)
- Make

## Project Structure

```
.
├── config/
│   └── pubsub-config.json    # PubSub configuration
├── service1/                 # Example service 1
├── service2/                 # Example service 2
├── src/                      # Main PubSub service
├── Makefile                  # Build and run commands
└── README.md                 # This file
```

## Configuration

The PubSub configuration is defined in `config/pubsub-config.json`. It includes:

- Topics and their subscriptions
- Push endpoints for subscriptions
- Message retention settings
- Push configuration attributes

Example configuration:
```json
{
  "topics": [
    {
      "name": "top5",
      "subscriptions": [
        {
          "name": "top5-sub1",
          "type": "push",
          "pushEndpoint": "http://host.docker.internal:3001/example",
          "ackDeadlineSeconds": 30,
          "messageRetentionDuration": "86400s",
          "pushConfig": {
            "attributes": {
              "x-goog-version": "v1",
              "x-goog-verify-token": "test-token"
            }
          }
        }
      ]
    }
  ]
}
```

## Setup and Running

1. Start the development environment:
```bash
make dev
```

This will:
- Start the PubSub emulator in a Docker container
- Install dependencies for all services
- Start all three services

2. Publish a message:
```bash
curl -X POST http://localhost:3000/publish \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello World", "topicName": "top5"}'
```

3. Clean up:
```bash
make clean
```

## Network Configuration

The PubSub emulator runs in a Docker container and communicates with local services using `host.docker.internal`. This allows the emulator to push messages to local services running on your machine.

## Push Notifications

The example includes a push subscription that sends messages to `service1` at `http://host.docker.internal:3001/example`. When a message is published to the `top5` topic:

1. The message is published to the topic
2. The emulator pushes the message to the configured endpoint
3. The service receives the message in the standard PubSub push format:
```json
{
  "subscription": "projects/gcp-pubsub-456020/subscriptions/top5-sub1",
  "message": {
    "data": "<base64-encoded-message>",
    "messageId": "1"
  }
}
```

## Troubleshooting

If you encounter issues:

1. Make sure Docker is running
2. Check that all services are running on their expected ports
3. Verify the PubSub emulator is accessible at `http://localhost:8085`
4. Ensure the push endpoint is correctly configured in `pubsub-config.json`

## License

MIT 