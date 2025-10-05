// services/transport-service/index.js
const { getProducer } = require("../kafka");

const run = async () => {
  const producer = getProducer();
  await producer.connect();

  // Simulate a trip update
  await producer.send({
    topic: "trips.updated",
    messages: [{ key: "trip-101", value: JSON.stringify({ tripId: 101, status: "DELAYED" }) }]
  });

  console.log("Trip update event sent");
};

run().catch(console.error);
