# Pub/Sub Emulator with UI

This project demonstrates a local development environment for Google Cloud Pub/Sub using the Pub/Sub emulator, with a custom UI for monitoring messages and a service architecture that mimics production setup.

## Architecture

The project consists of three main components:

1. **Service1 (Publisher)**: A service that publishes messages to Pub/Sub topics
2. **Service2 (Subscriber)**: A service that subscribes to Pub/Sub topics and processes messages
3. **Pub/Sub Emulator UI**: A custom web interface for monitoring Pub/Sub topics and messages

## Prerequisites

- Node.js (v18 or later)
- Bun (latest version)
- Google Cloud SDK (for Pub/Sub emulator)
- jq (for JSON processing)
- Make (for build automation)

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd pubsub-emulator-ui
```

2. Install dependencies for all components:
```bash
# Install UI dependencies
cd pubsub-emulator-ui/webapp
npm install

# Install Service1 dependencies
cd service1
bun install
cd ..

# Install Service2 dependencies
cd service2
bun install
cd ..
```

## Configuration

1. Create a `.env` file in the root directory:
```bash
PROJECT_ID=your-project-id
```

2. Configure Pub/Sub topics and subscriptions in `config/pubsub-config.json`:
```json
{
  "topics": [
    {
      "name": "notifications",
      "subscriptions": [
        {
          "name": "notifications-sub",
          "type": "push",
          "pushEndpoint": "http://localhost:3001/notifications",
          "ackDeadlineSeconds": 10,
          "messageRetentionDuration": "604800s"
        }
      ]
    }
  ]
}
```

## Running the Application

The project uses Makefiles for automation. Here are the available commands:

### Development Environment

```bash
# Start the entire development environment
make dev

# Or use individual commands
make dev-start  # Start development environment
make dev-stop   # Stop development environment
make clean      # Clean up all processes
```

This will start:
- Pub/Sub emulator on port 8790
- CORS proxy for UI access
- Service1 (Publisher) on port 3000
- Service2 (Subscriber) on port 3001
- UI on port 4200

### GCP Infrastructure Setup

```bash
# Set up GCP Pub/Sub infrastructure
make setup
```

### Utility Commands

```bash
# Check for required dependencies
make check-jq

# Clean up processes
make clean
```

## Accessing the Services

- Publisher Service (Service1): http://localhost:3000
- Subscriber Service (Service2): http://localhost:3001
- UI: http://localhost:4200

## Testing the System

1. Send a test message using curl:
```bash
curl -X POST http://localhost:3000/publish \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello World", "topicName": "notifications"}'
```

2. Check Service2's console to see the received message
3. Monitor the message flow in the UI at http://localhost:4200

## Project Structure

```
.
├── Makefile              # Main Makefile for project automation
├── scripts/
│   ├── setup-gcp.mk     # GCP infrastructure setup
│   ├── dev.mk           # Development environment management
│   └── setup-gcp.sh     # GCP setup script
├── service1/            # Publisher service
├── service2/            # Subscriber service
├── pubsub-emulator-ui/  # Custom UI for monitoring
└── config/
    └── pubsub-config.json  # Pub/Sub configuration
```

## Troubleshooting

1. If you see "port already in use" errors:
```bash
make clean  # This will kill all related processes
```

2. If the emulator fails to start:
```bash
# Check if the port is available
lsof -i :8790
# Kill any process using the port
kill -9 <PID>
```

3. If you see CORS errors in the UI:
```bash
# Restart the CORS proxy
make clean
make dev
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details. 