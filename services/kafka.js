// services/kafka.js
const { Kafka } = require("kafkajs");

const kafka = new Kafka({
  clientId: "smart-ticketing",
  brokers: ["kafka:9092"], // Use 'localhost:9092' if outside Docker network
});

const getProducer = () => kafka.producer();
const getConsumer = (groupId) => kafka.consumer({ groupId });

module.exports = { kafka, getProducer, getConsumer };
