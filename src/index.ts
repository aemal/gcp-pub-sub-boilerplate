import fastify from 'fastify';
import cors from '@fastify/cors';
import { PubSub, Topic, SubscriptionOptions, CreateSubscriptionOptions } from '@google-cloud/pubsub';
import fs from 'fs';
import path from 'path';

interface PushConfig {
  attributes?: {
    [key: string]: string;
  };
}

interface SubscriptionConfig {
  name: string;
  type: 'push' | 'pull';
  pushEndpoint?: string;
  ackDeadlineSeconds: number;
  messageRetentionDuration: string;
  pushConfig?: PushConfig;
}

interface TopicConfig {
  name: string;
  subscriptions: SubscriptionConfig[];
}

interface PubSubConfig {
  topics: TopicConfig[];
}

const app = fastify({
  logger: true
});

// Register CORS
await app.register(cors, {
  origin: true
});

// Initialize PubSub with emulator support
const emulatorHost = process.env.PUBSUB_EMULATOR_HOST;
const apiEndpoint = emulatorHost ? `http://${emulatorHost}` : undefined;
const projectId = process.env.PUBSUB_PROJECT_ID || 'gcp-pubsub-456020';

const pubsub = new PubSub({
  projectId,
  apiEndpoint
});

console.log('PubSub initialized with:', {
  projectId,
  apiEndpoint
});

// Initialize topics and subscriptions from config
async function initializePubSub() {
  try {
    // Initialize PubSub client
    const pubsub = new PubSub({
      projectId: process.env.PROJECT_ID,
      apiEndpoint: process.env.PUBSUB_EMULATOR_HOST,
    });

    // Load configuration
    const config = JSON.parse(
      fs.readFileSync(path.join(__dirname, "../config/pubsub-config.json"), "utf8")
    );

    console.log("Loaded Pub/Sub configuration:", JSON.stringify(config, null, 2));

    // Create topics and subscriptions
    for (const topicConfig of config.topics) {
      const topicName = topicConfig.name;
      const topic = pubsub.topic(topicName);

      // Check if topic exists
      const [topicExists] = await topic.exists();
      if (!topicExists) {
        console.log(`Topic ${topicName} does not exist, creating it...`);
        await topic.create();
        console.log(`Topic ${topicName} created successfully`);
      }

      // Create subscriptions
      console.log(
        `Topic ${topicName} has ${topicConfig.subscriptions.length} subscriptions:`,
        topicConfig.subscriptions.map((sub: { name: string }) => sub.name)
      );

      for (const subConfig of topicConfig.subscriptions) {
        const subName = subConfig.name;

        // Check if subscription exists
        const subscription = topic.subscription(subName);
        const [subExists] = await subscription.exists();

        if (!subExists) {
          console.log(`Creating subscription ${subName} for topic ${topicName}...`);
          const options: CreateSubscriptionOptions = {
            topic: topicName,
            ackDeadlineSeconds: subConfig.ackDeadlineSeconds,
            messageRetentionDuration: {
              seconds: parseInt(subConfig.messageRetentionDuration),
            },
          };

          if (subConfig.type === "push" && subConfig.pushEndpoint) {
            options.pushConfig = {
              pushEndpoint: subConfig.pushEndpoint,
              attributes: subConfig.pushConfig?.attributes || {},
            };
          }

          await topic.createSubscription(subName, options);
          console.log(
            `Subscription ${subName} created successfully with options:`,
            JSON.stringify(options, null, 2)
          );
        } else {
          console.log(`Subscription ${subName} already exists, skipping creation`);
        }
      }
    }

    console.log("PubSub configuration initialized successfully");
  } catch (error) {
    console.error("Error initializing PubSub:", error);
    process.exit(1);
  }
}

// Load Pub/Sub configuration
let pubsubConfig: PubSubConfig;
try {
  const configPath = path.resolve(process.cwd(), 'config/pubsub-config.json');
  const configData = fs.readFileSync(configPath, 'utf8');
  pubsubConfig = JSON.parse(configData) as PubSubConfig;
  console.log('Loaded Pub/Sub configuration:', pubsubConfig);
} catch (error) {
  console.error('Error loading Pub/Sub configuration:', error);
  pubsubConfig = { topics: [] };
}

// Initialize PubSub configuration after loading
await initializePubSub();

// Add this function to sync changes to GCP
async function syncToGCP() {
  try {
    const { execSync } = require('child_process');
    console.log('Syncing changes to GCP...');
    execSync('make sync-to-gcp', { stdio: 'inherit' });
  } catch (error) {
    console.error('Error syncing to GCP:', error);
  }
}

// Modify the ensureTopic function to sync after creation
async function ensureTopic(topicName: string): Promise<Topic> {
  const topic = pubsub.topic(topicName);
  const [exists] = await topic.exists();
  
  if (!exists) {
    console.log(`Topic ${topicName} does not exist, creating it...`);
    await topic.create();
    console.log(`Topic ${topicName} created successfully`);
    await syncToGCP(); // Sync to GCP after creating topic
  } else {
    console.log(`Topic ${topicName} already exists`);
  }

  // Get and log all subscriptions for this topic
  const [subscriptions] = await topic.getSubscriptions();
  console.log(`Topic ${topicName} has ${subscriptions.length} subscriptions:`, subscriptions.map(sub => ({
    name: sub.name,
    pushEndpoint: (sub.metadata as any)?.pushConfig?.pushEndpoint
  })));

  return topic;
}

// Health check endpoint
app.get('/health', async () => {
  return { status: 'ok' };
});

// Modify the publish endpoint to sync after publishing
app.post('/publish', async (request, reply) => {
  try {
    const { message, topicName = 'my-topic' } = request.body as { message: string, topicName?: string };
    
    if (!message) {
      return reply.code(400).send({ error: 'Message is required' });
    }

    const messageData = {
      message: message,
      timestamp: new Date().toISOString()
    };
    
    const data = Buffer.from(JSON.stringify(messageData));
    
    console.log('Publishing with config:', {
      projectId,
      apiEndpoint,
      topic: topicName,
      message: messageData
    });
    
    const topic = await ensureTopic(topicName);
    console.log('Topic exists, publishing message...');
    
    const messageId = await topic.publishMessage({ data });
    console.log('Message published successfully with ID:', messageId);

    // Get subscription details properly
    const [subscriptions] = await topic.getSubscriptions();
    for (const subscription of subscriptions) {
      const [subDetails] = await subscription.get();
      console.log('Subscription details:', {
        name: subDetails.name,
        pushEndpoint: subDetails.metadata?.pushConfig?.pushEndpoint,
        fullMetadata: subDetails.metadata
      });

      if (subDetails.metadata?.pushConfig?.pushEndpoint) {
        console.log('This is a push subscription. The emulator should attempt to push to:', subDetails.metadata.pushConfig.pushEndpoint);
        console.log('Push config:', {
          endpoint: subDetails.metadata.pushConfig.pushEndpoint,
          attributes: subDetails.metadata.pushConfig.attributes,
          state: subDetails.metadata.state
        });
      }
    }

    await new Promise(resolve => setTimeout(resolve, 1000));
    // await syncToGCP(); // Sync to GCP after publishing - Commented out to avoid expected errors during local dev

    return { messageId, topic: topicName };
  } catch (error) {
    console.error('Error publishing message:', error);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

// Subscribe to topic endpoint
app.post('/subscribe', async (request, reply) => {
  try {
    const { topicName = 'my-topic', subscriptionName = 'my-subscription' } = request.body as { 
      topicName?: string, 
      subscriptionName?: string 
    };

    const topic = await ensureTopic(topicName);
    const subscription = topic.subscription(subscriptionName);
    
    // Check if subscription exists
    const [exists] = await subscription.exists();
    if (!exists) {
      console.log(`Subscription ${subscriptionName} does not exist, creating it...`);
      await topic.createSubscription(subscriptionName);
      console.log(`Subscription ${subscriptionName} created successfully`);
    }

    // Set up message handler
    subscription.on('message', (message) => {
      console.log('Received message:', message.data.toString());
      message.ack();
    });

    subscription.on('error', (error) => {
      console.error('Received error:', error);
    });

    return { status: 'subscribed', topic: topicName, subscription: subscriptionName };
  } catch (error: unknown) {
    if (error instanceof Error) {
      console.error('Subscription error:', error);
      return reply.code(500).send({ error: 'Failed to subscribe', details: error.message });
    }
    return reply.code(500).send({ error: 'Failed to subscribe' });
  }
});

// Start the server
const start = async () => {
  try {
    await app.listen({ port: 3000, host: '0.0.0.0' });
    console.log('PubSub service is running on port 3000');
    console.log('Using Pub/Sub Emulator:', !!process.env.PUBSUB_EMULATOR_HOST);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
};

start(); 