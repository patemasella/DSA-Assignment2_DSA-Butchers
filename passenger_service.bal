import ballerina/http;
import ballerinax/postgresql;
import ballerina/log;
import ballerinax/kafka;
import ballerina/lang.'value;

configurable int passengerServicePort = 8080;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUsername = "transport_user";
configurable string dbPassword = "transport_password";
configurable string dbName = "transport_system";

configurable string kafkaBootstrapServers = "localhost:9092";

listener http:Listener passengerListener = new(passengerServicePort);

// Simple JWT validation (replace with proper JWT in production)
public isolated function validatePassengerAuth(string authHeader) returns string|error {
    if !authHeader.startsWith("Bearer passenger-") {
        return error("Invalid authentication");
    }
    // Extract passenger ID from token (simplified)
    return authHeader.replace("Bearer passenger-", "");
}

service /passenger on passengerListener {
    private final PassengerDBClient passengerDB;
    private final kafka:Producer kafkaProducer;

    function init() returns error? {
        postgresql:Client dbClient = check new (
            host = dbHost,
            user = dbUsername,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        self.passengerDB = new (dbClient);
        self.kafkaProducer = check new (kafkaBootstrapServers);
        
        log:printInfo("Passenger Service with Kafka started on port " + passengerServicePort.toString());
    }

    // ===== HEALTH CHECK =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/health"
    }
    resource function get health() returns string {
        return "Passenger Service is healthy!";
    }

    // ===== AUTHENTICATION =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/register"
    }
    resource function post register(PassengerRegisterRequest request) returns SuccessResponse|http:BadRequest|http:InternalServerError {
        log:printInfo("Registering new passenger: " + request.email);
        
        string|error passengerId = self.passengerDB.registerPassenger(request);
        if passengerId is error {
            log:printError("Registration failed", error = passengerId);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for user registration
        _ = self.sendKafkaEvent("notifications", {
            "eventType": "USER_REGISTERED",
            "userId": passengerId,
            "email": request.email,
            "firstName": request.firstName,
            "lastName": request.lastName,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "passenger-service"
        });

        return {
            message: "Passenger registered successfully",
            id: passengerId
        };
    }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/login"
    }
    resource function post login(PassengerLoginRequest request) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        log:printInfo("Login attempt: " + request.email);
        
        string|error passengerId = self.passengerDB.validatePassengerCredentials(request.email, request.password);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }
        
        // In production, generate proper JWT token
        string authToken = "passenger-" + passengerId;
        
        return {
            message: "Login successful",
            id: authToken
        };
    }

    // ===== TRIP SEARCH =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/trips/available"
    }
    resource function get trips/available(TripSearchRequest search) returns AvailableTripResponse[]|http:BadRequest|http:InternalServerError {
        log:printInfo("Searching trips: " + search.origin + " to " + search.destination + " on " + search.date);
        
        var trips = self.passengerDB.searchAvailableTrips(search);
        if trips is error {
            log:printError("Trip search failed", error = trips);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var trip in trips
            select {
                tripId: trip.trip_id.toString(),
                routeId: trip.route_id.toString(),
                origin: trip.origin.toString(),
                destination: trip.destination.toString(),
                scheduledDeparture: trip.scheduled_departure.toString(),
                scheduledArrival: trip.scheduled_arrival.toString(),
                vehicleNumber: trip.vehicle_number.toString(),
                vehicleType: trip.vehicle_type.toString(),
                driverName: trip.driver_name.toString(),
                availableSeats: <int>trip.available_seats,
                basePrice: <decimal>trip.base_price,
                status: trip.status.toString()
            };
    }

    // ===== TICKET MANAGEMENT WITH KAFKA =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/tickets/purchase"
    }
    resource function post tickets/purchase(@http:Header {name: "Authorization"} string authHeader,
                                           TicketPurchaseRequest request) returns SuccessResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        string|error passengerId = validatePassengerAuth(authHeader);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }
        
        log:printInfo("Ticket purchase request from passenger: " + passengerId);
        
        // For demo, use fixed price - in production, calculate based on trip and ticket type
        decimal ticketPrice = 5.00;
        
        string|error ticketId = self.passengerDB.createTicket(passengerId, request.tripId, request.ticketType, ticketPrice);
        if ticketId is error {
            log:printError("Ticket purchase failed", error = ticketId);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for ticket creation
        _ = self.sendKafkaEvent("ticket-events", {
            "eventType": "TICKET_CREATED",
            "ticketId": ticketId,
            "passengerId": passengerId,
            "tripId": request.tripId,
            "ticketType": request.ticketType,
            "price": ticketPrice,
            "status": "created",
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "passenger-service"
        });

        return {
            message: "Ticket purchased successfully",
            id: ticketId
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/tickets"
    }
    resource function get tickets(@http:Header {name: "Authorization"} string authHeader) returns TicketResponse[]|http:Unauthorized|http:InternalServerError {
        string|error passengerId = validatePassengerAuth(authHeader);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }
        
        var tickets = self.passengerDB.getPassengerTickets(passengerId);
        if tickets is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var ticket in tickets
            select {
                ticketId: ticket.ticket_id.toString(),
                tripId: "", // Will be filled from trip data
                ticketType: ticket.ticket_type.toString(),
                status: ticket.status.toString(),
                purchasePrice: <decimal>ticket.purchase_price,
                validFrom: ticket.valid_from.toString(),
                validUntil: ticket.valid_until.toString(),
                qrCodeHash: ticket.qr_code_hash?.toString(),
                createdAt: ticket.created_at.toString()
            };
    }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/tickets/{ticketId}/validate"
    }
    resource function post tickets/[string ticketId]/validate(@http:Header {name: "Authorization"} string authHeader) returns SuccessResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        string|error passengerId = validatePassengerAuth(authHeader);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }
        
        var isValid = self.passengerDB.validateTicket(ticketId, passengerId);
        if isValid is error || !isValid {
            return http:BAD_REQUEST;
        }

        // Send Kafka event for ticket validation
        _ = self.sendKafkaEvent("ticket-events", {
            "eventType": "TICKET_VALIDATED",
            "ticketId": ticketId,
            "passengerId": passengerId,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "passenger-service"
        });

        return {
            message: "Ticket validated successfully"
        };
    }

    // ===== PROFILE MANAGEMENT =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/profile"
    }
    resource function get profile(@http:Header {name: "Authorization"} string authHeader) returns PassengerResponse|http:Unauthorized|http:InternalServerError {
        string|error passengerId = validatePassengerAuth(authHeader);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }
        
        var profile = self.passengerDB.getPassengerProfile(passengerId);
        if profile is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return {
            id: profile.id.toString(),
            email: profile.email.toString(),
            firstName: profile.first_name.toString(),
            lastName: profile.last_name.toString(),
            phoneNumber: profile.phone_number?.toString(),
            isActive: profile.is_active of boolean ? profile.is_active : true,
            createdAt: profile.created_at.toString()
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