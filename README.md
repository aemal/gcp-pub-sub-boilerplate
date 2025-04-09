# PubSub Example

This project demonstrates a simple PubSub implementation using Google Cloud PubSub emulator. It consists of three services:

1. Main PubSub service (port 3000)
2. Example service 1 (port 3001)
3. Example service 2 (port 3002)

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