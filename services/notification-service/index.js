// services/notification-service/index.js
const { getProducer, getConsumer } = require("../kafka");

const run = async () => {
  const producer = getProducer();
  const consumer = getConsumer("notification-service-group");

  await producer.connect();
  await consumer.connect();

  // Subscribe to multiple topics
  const topics = ["tickets.created", "tickets.validated", "trips.updated"];
  for (const topic of topics) await consumer.subscribe({ topic, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ topic, message }) => {
      const event = JSON.parse(message.value.toString());
      console.log(`Notification triggered by ${topic}:`, event);

      await producer.send({
        topic: "notifications.sent",
        messages: [{ key: `${topic}-${event.ticketId || event.tripId}`, value: JSON.stringify(event) }]
      });
    }
  });
};

run().catch(console.error);
