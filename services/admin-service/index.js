// services/admin-service/index.js
const { getConsumer } = require("../kafka");

const run = async () => {
  const consumer = getConsumer("admin-service-group");
  await consumer.connect();

  const topics = ["ticket-events", "payment-events"];
  for (const topic of topics) await consumer.subscribe({ topic, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ topic, message }) => {
      const event = JSON.parse(message.value.toString());
      console.log(`Admin received event ${topic}:`, event);
    }
  });
};

run().catch(console.error);
