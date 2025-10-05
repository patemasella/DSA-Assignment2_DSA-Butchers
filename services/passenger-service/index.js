// services/passenger-service/index.js
const { getProducer } = require("../kafka");

const run = async () => {
  const producer = getProducer();
  await producer.connect();
  console.log("Passenger Service Producer Connected");

  // Simulate passenger registration
  await producer.send({
    topic: "passengers.registered",
    messages: [
      { key: "passenger-1", value: JSON.stringify({ passengerId: 1, name: "Alice" }) }
    ]
  });

  console.log("Passenger registration event sent");
};

run().catch(console.error);
