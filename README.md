# PubSub Service

A Fastify-based PubSub service with example REST endpoints.

## Project Structure

- `src/` - Main PubSub service implementation
- `service1/` - Example REST service 1
- `service2/` - Example REST service 2
- `config/` - Configuration files
- `scripts/` - Utility scripts

## Main PubSub Service

The main PubSub service runs on port 3000 and provides two main endpoints:

- `POST /publish` - Publish a message to a topic
- `POST /subscribe` - Subscribe to a topic

### Example Usage

```bash
# Publish a message
curl -X POST http://localhost:3000/publish \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, world!", "topicName": "my-topic"}'

# Subscribe to a topic
curl -X POST http://localhost:3000/subscribe \
  -H "Content-Type: application/json" \
  -d '{"topicName": "my-topic", "subscriptionName": "my-subscription"}'
```

## Example Services

### Service 1 (Port 3001)

Example REST service that demonstrates how to use the PubSub service for publishing messages.

### Service 2 (Port 3002)

Example REST service that demonstrates how to use the PubSub service for subscribing to messages.

## Quick Start

To start the entire development environment with a single command:

```bash
make dev
```

This will:
1. Clean up any existing processes
2. Install all dependencies
3. Start the PubSub emulator
4. Start all services

The services will be available at:
- Main PubSub service: http://localhost:3000
- Service1: http://localhost:3001
- Service2: http://localhost:3002
- PubSub emulator: http://localhost:8085

To stop all services:
```bash
make clean
```

## Manual Setup (if needed)

1. Install dependencies:
```bash
make install
```

2. Start the PubSub emulator:
```bash
make start-emulator
```

3. Start the services:
```bash
make start-services
```

## Environment Variables

Create a `.env` file with the following variables:

```
PUBSUB_EMULATOR_HOST=localhost:8085
PUBSUB_PROJECT_ID=your-project-id
```

## Development

- `bun run dev` - Start the development server
- `bun build` - Build the project
- `bun test` - Run tests 