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
async function initializeFromConfig() {
  try {
    console.log('Loaded Pub/Sub configuration:', pubsubConfig);
    
    for (const topicConfig of pubsubConfig.topics) {
      const topic = await ensureTopic(topicConfig.name);
      
      for (const subConfig of topicConfig.subscriptions) {
        console.log(`Creating subscription ${subConfig.name} for topic ${topicConfig.name}...`);
        
        const options: CreateSubscriptionOptions = {
          ackDeadlineSeconds: subConfig.ackDeadlineSeconds,
          messageRetentionDuration: {
            seconds: parseInt(subConfig.messageRetentionDuration.replace('s', ''))
          }
        };
        
        if (subConfig.type === 'push' && subConfig.pushEndpoint) {
          console.log('Setting push config:', {
            pushEndpoint: subConfig.pushEndpoint,
            attributes: subConfig.pushConfig?.attributes
          });
          options.pushConfig = {
            pushEndpoint: subConfig.pushEndpoint,
            attributes: subConfig.pushConfig?.attributes || {}
          };
        }
        
        try {
          await topic.createSubscription(subConfig.name, options);
          console.log(`Subscription ${subConfig.name} created successfully with options:`, options);

          // Verify subscription configuration
          if (subConfig.type === 'push') {
            const [subscription] = await topic.subscription(subConfig.name).get();
            console.log('Subscription details:', {
              name: subscription.name,
              pushEndpoint: subscription.metadata?.pushConfig?.pushEndpoint,
              pushConfig: subscription.metadata?.pushConfig,
              fullMetadata: subscription.metadata
            });
          }
        } catch (error) {
          console.error(`Error creating subscription ${subConfig.name}:`, error);
        }
      }
    }
    
    console.log('PubSub configuration initialized successfully');
  } catch (error) {
    console.error('Error initializing PubSub configuration:', error);
    throw error;
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
await initializeFromConfig();

// Ensure topic exists
async function ensureTopic(topicName: string): Promise<Topic> {
  const topic = pubsub.topic(topicName);
  const [exists] = await topic.exists();
  
  if (!exists) {
    console.log(`Topic ${topicName} does not exist, creating it...`);
    await topic.create();
    console.log(`Topic ${topicName} created successfully`);
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

// Publish message endpoint
app.post('/publish', async (request, reply) => {
  try {
    const { message, topicName = 'my-topic' } = request.body as { message: string, topicName?: string };
    
    if (!message) {
      return reply.code(400).send({ error: 'Message is required' });
    }

    // Create a properly formatted message for PubSub
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

      // Add logging for push subscription
      if (subDetails.metadata?.pushConfig?.pushEndpoint) {
        console.log('This is a push subscription. The emulator should attempt to push to:', subDetails.metadata.pushConfig.pushEndpoint);
        console.log('Push config:', {
          endpoint: subDetails.metadata.pushConfig.pushEndpoint,
          attributes: subDetails.metadata.pushConfig.attributes,
          state: subDetails.metadata.state
        });
      }
    }

    // Add a small delay to allow the emulator to process the message
    await new Promise(resolve => setTimeout(resolve, 1000));

    return { messageId, topic: topicName };
  } catch (error: unknown) {
    if (error instanceof Error) {
      console.error('Detailed publish error:', {
        error: error.message,
        code: (error as any).code,
        details: (error as any).details,
        stack: error.stack
      });
      return reply.code(500).send({ error: 'Failed to publish message', details: error.message });
    }
    return reply.code(500).send({ error: 'Failed to publish message' });
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