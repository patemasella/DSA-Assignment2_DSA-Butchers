import ballerinax/kafka;
import ballerina/crypto;
import ballerina/log;
import ballerina/random;
import ballerina/lang.'value;

configurable string kafkaBootstrapServers = "localhost:9092";
configurable string ticketEventsTopic = "ticket-events";
configurable string paymentEventsTopic = "payment-events";

configurable string qrCodeSecret = "ticketing-secret-key-2024";

public isolated client class TicketGenerator {
    private final kafka:Producer kafkaProducer;
    private final kafka:Consumer kafkaConsumer;
    private final TicketingDBClient ticketingDB;

    public function init(TicketingDBClient ticketingDB) returns error? {
        self.kafkaProducer = check new (kafkaBootstrapServers);
        
        kafka:ConsumerConfiguration consumerConfig = {
            groupId: "ticketing-service",
            offsetReset: "earliest",
            topics: [paymentEventsTopic],
            pollingInterval: 1000
        };
        self.kafkaConsumer = check new (kafkaBootstrapServers, consumerConfig);
        
        self.ticketingDB = ticketingDB;
        
        log:printInfo("Ticket generator initialized");
    }

    // ===== TICKET CREATION =====
    public function generateTicket(string passengerId, string tripId, string ticketType, decimal price) returns string|error {
        log:printInfo("Generating ticket for passenger: " + passengerId);
        
        // Generate QR code hash
        string qrCodeHash = self.generateQRCodeHash(passengerId, tripId, ticketType);
        
        // Create ticket in database
        string ticketId = check self.ticketingDB->createTicket(passengerId, tripId, ticketType, price, qrCodeHash);
        
        // Send ticket creation event
        check self.sendTicketEvent({
            eventType: "TICKET_CREATED",
            ticketId: ticketId,
            passengerId: passengerId,
            tripId: tripId,
            ticketType: ticketType,
            status: "created",
            price: price,
            timestamp: self.getCurrentTimestamp()
        });
        
        return ticketId;
    }

    // ===== TICKET VALIDATION =====
    public function validateTicketByQRCode(string qrCodeHash, string tripId) returns TicketValidationResponse|error {
        log:printInfo("Validating ticket with QR code: " + qrCodeHash);
        
        var ticket = self.ticketingDB->getTicketByQRCode(qrCodeHash);
        if ticket is error {
            return {
                isValid: false,
                message: "Invalid ticket QR code"
            };
        }
        
        // Check if ticket is for the correct trip
        if ticket.trip_id.toString() != tripId {
            return {
                isValid: false,
                message: "Ticket not valid for this trip"
            };
        }
        
        // Check ticket status
        string status = ticket.status.toString();
        if status != "paid") {
            return {
                isValid: false,
                message: "Ticket not paid. Status: " + status
            };
        }
        
        // Validate the ticket
        boolean isValid = check self.ticketingDB->validateTicket(ticket.id.toString(), tripId);
        
        if isValid {
            // Send validation event
            check self.sendValidationEvent({
                eventType: "TICKET_VALIDATED",
                ticketId: ticket.id.toString(),
                tripId: tripId,
                passengerId: ticket.passenger_id.toString(),
                isValid: true,
                timestamp: self.getCurrentTimestamp()
            });
            
            return {
                isValid: true,
                message: "Ticket validated successfully",
                ticketId: ticket.id.toString(),
                passengerName: ticket.passenger_name.toString(),
                ticketType: ticket.ticket_type.toString()
            };
        } else {
            return {
                isValid: false,
                message: "Ticket validation failed"
            };
        }
    }

    // ===== PAYMENT EVENT PROCESSING =====
    public function startPaymentListener() returns error? {
        log:printInfo("Starting payment event listener");
        
        while true {
            var result = self.kafkaConsumer->poll(1000);
            if result is kafka:Error[] {
                log:printError("Error polling Kafka", error = result[0]);
            } else if result is kafka:ConsumerRecord[] {
                foreach var record in result {
                    _ = check self.processPaymentEvent(record);
                }
                _ = check self.kafkaConsumer->commit();
            }
        }
    }

    private function processPaymentEvent(kafka:ConsumerRecord record) returns error? {
        string message = check string:fromBytes(record.value);
        log:printInfo("Received payment event: " + message);
        
        json parsedMessage = check value:fromJsonString(message);
        
        match parsedMessage {
            record {string eventType; string paymentId; string ticketId; string status;} => {
                if eventType == "PAYMENT_PROCESSED" {
                    string ticketStatus = status == "completed" ? "paid" : "created";
                    var updateResult = self.ticketingDB->updateTicketStatus(ticketId, ticketStatus);
                    
                    if updateResult is error {
                        log:printError("Failed to update ticket status", error = updateResult);
                    } else {
                        log:printInfo("Updated ticket " + ticketId + " status to: " + ticketStatus);
                        
                        // Send ticket status update event
                        check self.sendTicketEvent({
                            eventType: "TICKET_STATUS_UPDATED",
                            ticketId: ticketId,
                            passengerId: "", // Would get from ticket
                            tripId: "", // Would get from ticket
                            ticketType: "", // Would get from ticket
                            status: ticketStatus,
                            price: 0.0,
                            timestamp: self.getCurrentTimestamp()
                        });
                    }
                }
            }
            _ => {
                log:printWarn("Unknown event type in payment message");
            }
        }
    }

    // ===== PRIVATE METHODS =====
    private function generateQRCodeHash(string passengerId, string tripId, string ticketType) returns string {
        string data = passengerId + "|" + tripId + "|" + ticketType + "|" + qrCodeSecret;
        return crypto:hashSha256(data.toBytes()).toBase16();
    }

    private function getCurrentTimestamp() returns string {
        return string `${{time:utcNow().format("yyyy-MM-dd'T'HH:mm:ss'Z'")}}`;
    }

    private function sendTicketEvent(TicketEvent event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        check self.kafkaProducer->send({
            topic: ticketEventsTopic,
            value: eventJson.toBytes()
        });
        log:printInfo("Sent ticket event: " + event.eventType);
    }

    private function sendValidationEvent(TicketValidationEvent event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        check self.kafkaProducer->send({
            topic: ticketEventsTopic,
            value: eventJson.toBytes()
        });
        log:printInfo("Sent validation event: " + event.eventType);
    }

    public function close() returns error? {
        _ = check self.kafkaProducer->close();
        return self.kafkaConsumer->close();
    }
}