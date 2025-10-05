import ballerina/http;
import ballerinax/postgresql;
import ballerina/jwt;
import ballerina/log;
import ballerinax/kafka;
import ballerina/lang.'value;

configurable int adminServicePort = 8085;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUsername = "transport_user";
configurable string dbPassword = "transport_password";
configurable string dbName = "transport_system";
configurable int dbMaxOpenConnections = 10;

configurable string jwtSecret = "admin-secret-key-2024-transport-system";
configurable string kafkaBootstrapServers = "localhost:9092";

listener http:Listener adminListener = new(adminServicePort);

// Simple JWT validator for admin authentication
public isolated function validateAdminAuth(string authHeader) returns boolean {
    return authHeader.startsWith("Bearer admin-token-");
}

service /admin on adminListener {
    private final AdminDBClient adminDB;
    private final kafka:Producer kafkaProducer;

    function init() returns error? {
        postgresql:Client dbClient = check new (
            host = dbHost,
            user = dbUsername,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        self.adminDB = new (dbClient);
        self.kafkaProducer = check new (kafkaBootstrapServers);
        
        log:printInfo("Admin Service with Kafka started on port " + adminServicePort.toString());
    }

    // ===== HEALTH CHECK =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/health"
    }
    resource function get health() returns string {
        return "Admin Service is healthy!";
    }

    // ===== USER MANAGEMENT ENDPOINTS =====

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/users"
    }
    resource function post users(@http:Header {name: "Authorization"} string authHeader,
                                 CreateUserRequest userRequest) returns string|http:Unauthorized|http:BadRequest|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        string|error userId = self.adminDB.createUser(userRequest);
        if userId is error {
            log:printError("Failed to create user", error = userId);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for user creation
        _ = self.sendKafkaEvent("admin-notifications", {
            "eventType": "USER_CREATED",
            "userId": userId,
            "email": userRequest.email,
            "role": userRequest.role,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "admin-service"
        });

        return userId;
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/users"
    }
    resource function get users(@http:Header {name: "Authorization"} string authHeader,
                                string? role) returns UserResponse[]|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var users = self.adminDB.getAllUsers(role);
        if users is error {
            log:printError("Failed to get users", error = users);
            return http:INTERNAL_SERVER_ERROR;
        }

        return from var user in users
            select {
                id: user.id.toString(),
                email: user.email.toString(),
                firstName: user.first_name.toString(),
                lastName: user.last_name.toString(),
                role: user.role.toString(),
                phoneNumber: user.phone_number?.toString(),
                isActive: user.is_active of boolean ? user.is_active : true,
                createdAt: user.created_at.toString(),
                updatedAt: user.updated_at.toString()
            };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/users/{userId}"
    }
    resource function get users/[string userId](@http:Header {name: "Authorization"} string authHeader) 
            returns UserResponse|http:Unauthorized|http:NotFound|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var user = self.adminDB.getUserById(userId);
        if user is error {
            return http:NOT_FOUND;
        }

        return {
            id: user.id.toString(),
            email: user.email.toString(),
            firstName: user.first_name.toString(),
            lastName: user.last_name.toString(),
            role: user.role.toString(),
            phoneNumber: user.phone_number?.toString(),
            isActive: user.is_active of boolean ? user.is_active : true,
            createdAt: user.created_at.toString(),
            updatedAt: user.updated_at.toString()
        };
    }

    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/users/{userId}"
    }
    resource function put users/[string userId](@http:Header {name: "Authorization"} string authHeader,
                                               UpdateUserRequest userRequest) returns http:Ok|http:Unauthorized|http:NotFound|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var result = self.adminDB.updateUser(userId, userRequest);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        return http:OK;
    }

    @http:ResourceConfig {
        methods: ["DELETE"],
        path: "/users/{userId}"
    }
    resource function delete users/[string userId](@http:Header {name: "Authorization"} string authHeader) 
            returns http:Ok|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var result = self.adminDB.deleteUser(userId);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        return http:OK;
    }

    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/users/{userId}/role"
    }
    resource function put users/[string userId]/role(@http:Header {name: "Authorization"} string authHeader,
                                                     string newRole) returns http:Ok|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var result = self.adminDB.changeUserRole(userId, newRole);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        return http:OK;
    }

    // ===== ROUTE MANAGEMENT ENDPOINTS =====

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/routes"
    }
    resource function post routes(@http:Header {name: "Authorization"} string authHeader,
                                  CreateRouteRequest routeRequest) returns string|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        string|error routeId = self.adminDB.createRoute(routeRequest);
        if routeId is error {
            log:printError("Failed to create route", error = routeId);
            return http:INTERNAL_SERVER_ERROR;
        }
        return routeId;
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/routes"
    }
    resource function get routes(@http:Header {name: "Authorization"} string authHeader) 
            returns RouteResponse[]|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var routes = self.adminDB.getAllRoutes();
        if routes is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        return from var route in routes
            select {
                id: route.id.toString(),
                routeCode: route.route_code.toString(),
                origin: route.origin.toString(),
                destination: route.destination.toString(),
                distanceKm: <decimal>route.distance_km,
                estimatedDurationMinutes: <int>route.estimated_duration_minutes,
                isActive: route.is_active of boolean ? route.is_active : true,
                createdAt: route.created_at.toString()
            };
    }

    // ===== TRIP MANAGEMENT ENDPOINTS WITH KAFKA =====

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/trips"
    }
    resource function post trips(@http:Header {name: "Authorization"} string authHeader,
                                 CreateTripRequest tripRequest) returns string|http:Unauthorized|http:BadRequest|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        string|error tripId = self.adminDB.createTrip(tripRequest);
        if tripId is error {
            log:printError("Failed to create trip", error = tripId);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for trip creation
        _ = self.sendKafkaEvent("trip-events", {
            "eventType": "TRIP_CREATED",
            "tripId": tripId,
            "routeId": tripRequest.routeId,
            "vehicleId": tripRequest.vehicleId,
            "driverId": tripRequest.driverId,
            "scheduledDeparture": tripRequest.scheduledDeparture,
            "scheduledArrival": tripRequest.scheduledArrival,
            "basePrice": tripRequest.basePrice,
            "status": "scheduled",
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "admin-service"
        });

        return tripId;
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/trips"
    }
    resource function get trips(@http:Header {name: "Authorization"} string authHeader,
                                string? status) returns map<anydata>[]|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var trips = self.adminDB.getAllTrips(status);
        if trips is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        return trips;
    }

    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/trips/{tripId}/status"
    }
    resource function put trips/[string tripId]/status(@http:Header {name: "Authorization"} string authHeader,
                                                       string status) returns http:Ok|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var result = self.adminDB.updateTripStatus(tripId, status);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for trip status update
        _ = self.sendKafkaEvent("trip-events", {
            "eventType": "TRIP_STATUS_UPDATED",
            "tripId": tripId,
            "status": status,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "admin-service"
        });

        return http:OK;
    }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/trips/{tripId}/cancel"
    }
    resource function post trips/[string tripId]/cancel(@http:Header {name: "Authorization"} string authHeader,
                                                        string reason) returns http:Ok|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var result = self.adminDB.cancelTrip(tripId, reason);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        return http:OK;
    }

    // ===== SERVICE DISRUPTIONS WITH KAFKA =====

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/trip-updates"
    }
    resource function post trip-updates(@http:Header {name: "Authorization"} string authHeader,
                                        TripUpdateRequest updateRequest) returns http:Ok|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        string adminId = "admin-system";
        var result = self.adminDB.createTripUpdate(updateRequest, adminId);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for trip update
        _ = self.sendKafkaEvent("trip-events", {
            "eventType": "TRIP_UPDATE_CREATED",
            "tripId": updateRequest.tripId,
            "updateType": updateRequest.updateType,
            "message": updateRequest.message,
            "delayMinutes": updateRequest.delayMinutes,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "admin-service"
        });

        // Also send to notifications for passenger alerts
        _ = self.sendKafkaEvent("notifications", {
            "eventType": "TRIP_UPDATE_NOTIFICATION",
            "tripId": updateRequest.tripId,
            "title": "Trip Update",
            "message": updateRequest.message,
            "notificationType": "trip_update",
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "admin-service"
        });

        return http:OK;
    }

    // ===== SYSTEM NOTIFICATIONS WITH KAFKA =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/system/notifications"
    }
    resource function post system/notifications(@http:Header {name: "Authorization"} string authHeader,
                                               NotificationRequest request) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        log:printInfo("Creating system notification: " + request.title);

        var result = self.adminDB.createSystemNotification(request.title, request.message, request.notificationType);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for system notification
        _ = self.sendKafkaEvent("admin-notifications", {
            "eventType": "SYSTEM_NOTIFICATION_CREATED",
            "title": request.title,
            "message": request.message,
            "notificationType": request.notificationType,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "admin-service"
        });

        return {
            message: result
        };
    }

    // ===== REPORTING ENDPOINTS =====

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/reports/sales"
    }
    resource function get reports/sales(@http:Header {name: "Authorization"} string authHeader,
                                        string startDate, string endDate, string? ticketType) 
            returns SalesReportResponse|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var sales = self.adminDB.getSalesReport(startDate, endDate, ticketType);
        if sales is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        return from var sale in sales
            select {
                date: sale.sale_date.toString(),
                ticketType: sale.ticket_type.toString(),
                hourSlot: <int>sale.hour_slot,
                amountSold: <decimal>sale.amount_sold,
                ticketsCount: <int>sale.tickets_count
            };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/reports/stats"
    }
    resource function get reports/stats(@http:Header {name: "Authorization"} string authHeader) 
            returns SystemStats|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var stats = self.adminDB.getSystemStats();
        if stats is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        return {
            totalUsers: <int>stats.total_users,
            activeTrips: <int>stats.active_trips,
            ticketsSoldToday: <int>stats.tickets_sold_today,
            revenueToday: <decimal>stats.revenue_today,
            totalRoutes: <int>stats.total_routes,
            activeVehicles: <int>stats.active_vehicles
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/reports/passenger-traffic"
    }
    resource function get reports/passenger-traffic(@http:Header {name: "Authorization"} string authHeader,
                                                    string startDate, string endDate) 
            returns PassengerTraffic|http:Unauthorized|http:InternalServerError {
        if !validateAdminAuth(authHeader) {
            return http:UNAUTHORIZED;
        }

        var traffic = self.adminDB.getPassengerTraffic(startDate, endDate);
        if traffic is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        return from var t in traffic
            select {
                travelDate: t.travel_date.toString(),
                passengerCount: <int>t.passenger_count,
                uniquePassengers: <int>t.unique_passengers
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