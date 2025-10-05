// services/payment-service/index.js
const { getProducer, getConsumer } = require("../kafka");

const run = async () => {
  const producer = getProducer();
  const consumer = getConsumer("payment-service-group");

  await producer.connect();
  await consumer.connect();

  await consumer.subscribe({ topic: "payments.requested", fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }) => {
      const payment = JSON.parse(message.value.toString());
      console.log("Payment requested:", payment);

      // Simulate payment confirmation
      await producer.send({
        topic: "payments.confirmed",
        messages: [{ key: `payment-${payment.ticketId}`, value: JSON.stringify(payment) }]
      });

      console.log("Payment confirmed sent");
    }
  });
};

run().catch(console.error);
