// services/kafka.js
const { Kafka } = require("kafkajs");

// Use environment variable if set, otherwise default to Docker network
const brokers = process.env.KAFKA_BROKERS
  ? process.env.KAFKA_BROKERS.split(",")
  : ["kafka:9092"];

const kafka = new Kafka({
  clientId: "smart-ticketing",
  brokers,
});

// Create a producer
const getProducer = async () => {
  const producer = kafka.producer();
  await producer.connect();
  console.log("Producer connected");
  return producer;
};

// Helper to send a message to a topic
const sendMessage = async (producer, topic, message) => {
  try {
    await producer.send({
      topic,
      messages: [{ value: JSON.stringify(message) }],
    });
    console.log(`Sent message to ${topic}`);
  } catch (err) {
    console.error("Error sending message:", err);
  }
};

// Create a consumer and subscribe to topics
const getConsumer = async (groupId, topics = []) => {
  const consumer = kafka.consumer({ groupId });
  await consumer.connect();
  console.log(`Consumer connected with groupId: ${groupId}`);

  for (const topic of topics) {
    await consumer.subscribe({ topic, fromBeginning: true });
    console.log(`Subscribed to topic: ${topic}`);
  }

  return consumer;
};

// Run a consumer with a handler function
const consumeMessages = async (consumer, handler) => {
  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      try {
        const data = JSON.parse(message.value.toString());
        await handler(data, topic, partition);
      } catch (err) {
        console.error("Error handling message:", err);
      }
    },
  });
};

// Disconnect producer and consumer gracefully
const shutdown = async (producer, consumer) => {
  if (producer) await producer.disconnect();
  if (consumer) await consumer.disconnect();
  console.log("Kafka connections closed");
};

module.exports = {
  kafka,
  getProducer,
  getConsumer,
  sendMessage,
  consumeMessages,
  shutdown,
};
