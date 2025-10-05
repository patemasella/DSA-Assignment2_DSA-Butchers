import ballerina/http;
import ballerinax/postgresql;
import ballerina/log;
import ballerinax/kafka;
import ballerina/lang.'value;

configurable int ticketingServicePort = 8084;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUsername = "transport_user";
configurable string dbPassword = "transport_password";
configurable string dbName = "transport_system";

configurable string kafkaBootstrapServers = "localhost:9092";

listener http:Listener ticketingListener = new(ticketingServicePort);

// Simple authentication validation
public isolated function validateAuth(string authHeader) returns string|error {
    if !authHeader.startsWith("Bearer ") {
        return error("Invalid authentication");
    }
    return authHeader.replace("Bearer ", "");
}

service /ticketing on ticketingListener {
    private final TicketingDBClient ticketingDB;
    private final TicketGenerator ticketGenerator;
    private final kafka:Producer kafkaProducer;
    private final kafka:Consumer kafkaConsumer;

    function init() returns error? {
        postgresql:Client dbClient = check new (
            host = dbHost,
            user = dbUsername,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        self.ticketingDB = new (dbClient);
        self.ticketGenerator = check new (self.ticketingDB);
        self.kafkaProducer = check new (kafkaBootstrapServers);
        
        // Initialize Kafka consumer for payment events
        kafka:ConsumerConfiguration consumerConfig = {
            groupId: "ticketing-service",
            offsetReset: "earliest",
            topics: ["payment-events", "trip-events"],
            pollingInterval: 1000
        };
        self.kafkaConsumer = check new (kafkaBootstrapServers, consumerConfig);
        
        // Start background services
        start self.consumePaymentEvents();
        start self.paymentEventListener();
        
        log:printInfo("Ticketing Service with Kafka started on port " + ticketingServicePort.toString());
    }

    // ===== BACKGROUND PAYMENT EVENT LISTENER =====
    isolated function paymentEventListener() returns error? {
        log:printInfo("Starting payment event listener for Ticketing Service");
        
        while true {
            var result = self.kafkaConsumer->poll(1000);
            if result is kafka:ConsumerRecord[] {
                foreach var record in result {
                    _ = check self.processPaymentEvent(record);
                }
                _ = check self.kafkaConsumer->commit();
            }
        }
    }

    private function processPaymentEvent(kafka:ConsumerRecord record) returns error? {
        string message = check string:fromBytes(record.value);
        json event = check value:fromJsonString(message);
        
        string eventType = event.eventType.toString();
        
        if eventType == "PAYMENT_PROCESSED" {
            await self.handlePaymentProcessed(event);
        } else if eventType == "TRIP_CANCELLED" || eventType == "TRIP_DELAYED" {
            await self.handleTripUpdate(event);
        }
    }

    private function handlePaymentProcessed(json event) returns error? {
        string ticketId = event.ticketId.toString();
        string status = event.status.toString();
        
        string ticketStatus = status == "completed" ? "paid" : "created";
        var updateResult = self.ticketingDB.updateTicketStatus(ticketId, ticketStatus);
        
        if updateResult is error {
            log:printError("Failed to update ticket status", error = updateResult);
        } else {
            log:printInfo("Updated ticket " + ticketId + " status to: " + ticketStatus);
            
            // Send ticket status update event
            _ = self.sendKafkaEvent("ticket-events", {
                "eventType": "TICKET_STATUS_UPDATED",
                "ticketId": ticketId,
                "status": ticketStatus,
                "paymentStatus": status,
                "timestamp": self.getCurrentTimestamp(),
                "sourceService": "ticketing-service"
            });

            // If payment successful, send notification
            if status == "completed") {
                _ = self.sendKafkaEvent("notifications", {
                    "eventType": "TICKET_PURCHASE_SUCCESS",
                    "ticketId": ticketId,
                    "userId": event.passengerId.toString(),
                    "title": "Ticket Purchase Successful",
                    "message": "Your ticket has been confirmed!",
                    "notificationType": "ticket_confirmation",
                    "timestamp": self.getCurrentTimestamp(),
                    "sourceService": "ticketing-service"
                });
            }
        }
    }

    private function handleTripUpdate(json event) returns error? {
        string tripId = event.tripId.toString();
        string eventType = event.eventType.toString();
        
        // Get all tickets for this trip
        var searchResult = self.ticketingDB.searchTickets({
            tripId: tripId,
            status: "paid"
        });
        
        if searchResult is map<anydata>[] {
            foreach var ticket in searchResult {
                // Send notification event for each affected ticket
                _ = self.sendKafkaEvent("notifications", {
                    "eventType": "TRIP_UPDATE_NOTIFICATION",
                    "userId": ticket.passenger_id.toString(),
                    "title": "Trip Update",
                    "message": event.message?.toString() ?: "Your trip has been updated",
                    "notificationType": "trip_update",
                    "tripId": tripId,
                    "ticketId": ticket.id.toString(),
                    "timestamp": self.getCurrentTimestamp(),
                    "sourceService": "ticketing-service"
                });
            }
        }
    }

    // Background task for payment event consumption
    isolated function consumePaymentEvents() returns error? {
        check self.ticketGenerator.startPaymentListener();
    }

    // ===== HEALTH CHECK =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/health"
    }
    resource function get health() returns string {
        return "Ticketing Service is healthy!";
    }

    // ===== TICKET CREATION =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/tickets"
    }
    resource function post tickets(@http:Header {name: "Authorization"} string authHeader,
                                  TicketCreateRequest request) returns SuccessResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        string|error passengerId = validateAuth(authHeader);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }

        // Validate that the passenger ID matches
        if passengerId != request.passengerId {
            return http:UNAUTHORIZED;
        }

        log:printInfo("Creating ticket for passenger: " + request.passengerId);
        
        // For demo, use fixed price - in production, calculate based on trip and ticket type
        decimal ticketPrice = 5.00;
        
        string|error ticketId = self.ticketGenerator->generateTicket(request.passengerId, request.tripId, request.ticketType, ticketPrice);
        if ticketId is error {
            log:printError("Ticket creation failed", error = ticketId);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for ticket creation
        _ = self.sendKafkaEvent("ticket-events", {
            "eventType": "TICKET_CREATED",
            "ticketId": ticketId,
            "passengerId": request.passengerId,
            "tripId": request.tripId,
            "ticketType": request.ticketType,
            "price": ticketPrice,
            "status": "created",
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "ticketing-service"
        });
        
        return {
            message: "Ticket created successfully",
            id: ticketId
        };
    }

    // ===== TICKET RETRIEVAL =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/tickets/{ticketId}"
    }
    resource function get tickets/[string ticketId](@http:Header {name: "Authorization"} string authHeader) 
            returns TicketResponse|http:Unauthorized|http:NotFound|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var ticket = self.ticketingDB->getTicket(ticketId);
        if ticket is error {
            return http:NOT_FOUND;
        }
        
        return {
            ticketId: ticket.id.toString(),
            passengerId: ticket.passenger_id.toString(),
            tripId: ticket.trip_id.toString(),
            ticketType: ticket.ticket_type.toString(),
            status: ticket.status.toString(),
            purchasePrice: <decimal>ticket.purchase_price,
            validFrom: ticket.valid_from.toString(),
            validUntil: ticket.valid_until.toString(),
            qrCodeHash: ticket.qr_code_hash?.toString(),
            boardingTime: ticket.boarding_time?.toString(),
            seatNumber: ticket.seat_number?.toString(),
            createdAt: ticket.created_at.toString(),
            updatedAt: ticket.updated_at.toString()
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/tickets"
    }
    resource function get tickets(@http:Header {name: "Authorization"} string authHeader,
                                 int? limit, int? offset) returns TicketResponse[]|http:Unauthorized|http:InternalServerError {
        string|error passengerId = validateAuth(authHeader);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }
        
        int actualLimit = limit ?: 50;
        int actualOffset = offset ?: 0;
        
        var tickets = self.ticketingDB->getPassengerTickets(passengerId, actualLimit, actualOffset);
        if tickets is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var ticket in tickets
            select {
                ticketId: ticket.id.toString(),
                passengerId: passengerId,
                tripId: ticket.trip_id.toString(),
                ticketType: ticket.ticket_type.toString(),
                status: ticket.status.toString(),
                purchasePrice: <decimal>ticket.purchase_price,
                validFrom: ticket.valid_from.toString(),
                validUntil: ticket.valid_until.toString(),
                qrCodeHash: (), // Not returned in list for security
                boardingTime: (),
                seatNumber: (),
                createdAt: ticket.created_at.toString(),
                updatedAt: ticket.created_at.toString() // Use created_at as updated_at in list
            };
    }

    // ===== TICKET VALIDATION WITH KAFKA =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/tickets/validate"
    }
    resource function post tickets/validate(TicketValidationRequest request) returns TicketValidationResponse|http:BadRequest|http:InternalServerError {
        log:printInfo("Validating ticket with QR code for trip: " + request.tripId);
        
        var ticket = self.ticketingDB.getTicketByQRCode(request.qrCodeHash);
        if ticket is error {
            return {
                isValid: false,
                message: "Invalid ticket QR code"
            };
        }
        
        // Check if ticket is for the correct trip
        if ticket.trip_id.toString() != request.tripId {
            return {
                isValid: false,
                message: "Ticket not valid for this trip"
            };
        }
        
        // Validate the ticket
        boolean isValid = check self.ticketingDB.validateTicket(ticket.id.toString(), request.tripId);
        
        if isValid {
            // Send validation event
            _ = self.sendKafkaEvent("ticket-events", {
                "eventType": "TICKET_VALIDATED",
                "ticketId": ticket.id.toString(),
                "tripId": request.tripId,
                "passengerId": ticket.passenger_id.toString(),
                "isValid": true,
                "timestamp": self.getCurrentTimestamp(),
                "sourceService": "ticketing-service"
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

    // ===== TICKET SEARCH (Admin) =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/tickets/search"
    }
    resource function get tickets/search(@http:Header {name: "Authorization"} string authHeader,
                                        TicketSearchRequest search) returns TicketResponse[]|http:Unauthorized|http:InternalServerError {
        if !authHeader.startsWith("Bearer admin-") {
            return http:UNAUTHORIZED;
        }
        
        var tickets = self.ticketingDB->searchTickets(search);
        if tickets is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var ticket in tickets
            select {
                ticketId: ticket.id.toString(),
                passengerId: ticket.passenger_id.toString(),
                tripId: ticket.trip_id.toString(),
                ticketType: ticket.ticket_type.toString(),
                status: ticket.status.toString(),
                purchasePrice: <decimal>ticket.purchase_price,
                validFrom: ticket.valid_from?.toString() ?: "",
                validUntil: ticket.valid_until?.toString() ?: "",
                qrCodeHash: (),
                boardingTime: (),
                seatNumber: (),
                createdAt: ticket.created_at.toString(),
                updatedAt: ticket.created_at.toString()
            };
    }

    // ===== TICKET STATISTICS =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/stats"
    }
    resource function get stats(@http:Header {name: "Authorization"} string authHeader) returns TicketStatsResponse|http:Unauthorized|http:InternalServerError {
        if !authHeader.startsWith("Bearer admin-") {
            return http:UNAUTHORIZED;
        }
        
        var stats = self.ticketingDB->getTicketStats();
        if stats is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return {
            totalTickets: <int>stats.total_tickets,
            activeTickets: <int>stats.active_tickets,
            validatedTickets: <int>stats.validated_tickets,
            expiredTickets: <int>stats.expired_tickets,
            totalRevenue: <decimal>stats.total_revenue
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/stats/trips/{tripId}"
    }
    resource function get stats/trips/[string tripId](@http:Header {name: "Authorization"} string authHeader) 
            returns map<anydata>|http:Unauthorized|http:InternalServerError {
        if !authHeader.startsWith("Bearer admin-") {
            return http:UNAUTHORIZED;
        }
        
        var stats = self.ticketingDB->getTripTicketStats(tripId);
        if stats is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return stats;
    }

    // ===== TICKET MANAGEMENT =====
    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/tickets/{ticketId}/cancel"
    }
    resource function put tickets/[string ticketId]/cancel(@http:Header {name: "Authorization"} string authHeader) 
            returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var result = self.ticketingDB->cancelTicket(ticketId);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send cancellation event
        _ = self.sendKafkaEvent("ticket-events", {
            "eventType": "TICKET_CANCELLED",
            "ticketId": ticketId,
            "passengerId": userId,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "ticketing-service"
        });
        
        return {
            message: "Ticket cancelled successfully"
        };
    }

    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/tickets/{ticketId}/seat"
    }
    resource function put tickets/[string ticketId]/seat(@http:Header {name: "Authorization"} string authHeader,
                                                        string seatNumber) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        if !authHeader.startsWith("Bearer admin-") {
            return http:UNAUTHORIZED;
        }
        
        var result = self.ticketingDB->updateTicketSeat(ticketId, seatNumber);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send seat assignment event
        _ = self.sendKafkaEvent("ticket-events", {
            "eventType": "TICKET_SEAT_ASSIGNED",
            "ticketId": ticketId,
            "seatNumber": seatNumber,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "ticketing-service"
        });
        
        return {
            message: "Seat assigned successfully"
        };
    }

    // ===== KAFKA HELPER METHODS =====
    private function sendKafkaEvent(string topic, map<json> event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        kafka:ProducerError? result = self.kafkaProducer->send({
            topic: topic,
            value: eventJson.toBytes()
        });
        
        if result is kafka:ProducerError {
            log:printError("Failed to send Kafka event to topic: " + topic, error = result);
            return result;
        }
        
        log:printInfo("Event sent to Kafka topic: " + topic + " | Type: " + event.get("eventType").toString());
    }

    private function getCurrentTimestamp() returns string {
        return string `${{time:utcNow().format("yyyy-MM-dd'T'HH:mm:ss'Z'")}}`;
    }
}