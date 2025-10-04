import ballerina/http;
import ballerina/log;
import ballerina/kafka;
import ballerina/uuid;
import ballerina/time;

listener http:Listener paymentListener = new(8082);

kafka:ProducerConfig producerConfig = { bootstrapServers: "kafka:9092" };
kafka:Producer producer = new(producerConfig);

service /payments on paymentListener {
    // Simulate payment (synchronous HTTP endpoint)
    resource function post simulate(@http:Payload json payload) returns json|error {
        string paymentId = "pay-" + uuid:create();
        // simulate processing delay...
        // produce payments.processed event
        json evt = {
            eventId: uuid:create(),
            type: "PAYMENT_COMPLETED",
            timestamp: time:currentTime().toString(),
            payload: {
                paymentId: paymentId,
                ticketId: payload.ticketId,
                amount: payload.amount,
                status: "SUCCESS"
            }
        };

        var r = producer->send({ topic: "payments.processed", value: evt.toJsonString() });
        if (r is error) {
            log:printError("Failed to publish payment", 'error = r);
            return { error: "Kafka publish failed" };
        }

        return { paymentId: paymentId, status: "SUCCESS" };
    }
}
