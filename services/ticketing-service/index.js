// services/ticketing-service/index.js
const { getProducer, getConsumer } = require("../kafka");

const run = async () => {
  const producer = getProducer();
  const consumer = getConsumer("ticketing-service-group");

  await producer.connect();
  await consumer.connect();

  await consumer.subscribe({ topic: "payments.confirmed", fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }) => {
      const payment = JSON.parse(message.value.toString());
      console.log("Received confirmed payment:", payment);

      // Produce ticket created event
      await producer.send({
        topic: "tickets.created",
        messages: [
          { key: `ticket-${payment.ticketId}`, value: JSON.stringify({ ...payment, status: "CREATED" }) }
        ]
      });

      console.log("Ticket created event sent");
    }
  });
};

run().catch(console.error);
