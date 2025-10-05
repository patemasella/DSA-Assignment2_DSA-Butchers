import ballerina/http;
import ballerinax/postgresql;
import ballerina/log;
import ballerinax/kafka;
import ballerina/lang.'value;

configurable int transportServicePort = 8081;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUsername = "transport_user";
configurable string dbPassword = "transport_password";
configurable string dbName = "transport_system";

configurable string kafkaBootstrapServers = "localhost:9092";

listener http:Listener transportListener = new(transportServicePort);

// Simple authentication validation
public isolated function validateAuth(string authHeader) returns string|error {
    if !authHeader.startsWith("Bearer ") {
        return error("Invalid authentication");
    }
    return authHeader.replace("Bearer ", "");
}

public isolated function isAdmin(string authHeader) returns boolean {
    return authHeader.startsWith("Bearer admin-");
}

public isolated function isDriver(string authHeader) returns boolean {
    return authHeader.startsWith("Bearer driver-");
}

service /transport on transportListener {
    private final TransportDBClient transportDB;
    private final TripManager tripManager;
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
        self.transportDB = new (dbClient);
        self.tripManager = check new (self.transportDB);
        self.kafkaProducer = check new (kafkaBootstrapServers);
        
        // Initialize Kafka consumer for trip updates
        kafka:ConsumerConfiguration consumerConfig = {
            groupId: "transport-service",
            offsetReset: "earliest",
            topics: ["trip-events", "vehicle-updates"],
            pollingInterval: 1000
        };
        self.kafkaConsumer = check new (kafkaBootstrapServers, consumerConfig);
        
        // Start background services
        start self.autoCompleteTrips();
        start self.kafkaEventListener();
        
        log:printInfo("Transport Service with Kafka started on port " + transportServicePort.toString());
    }

    // ===== BACKGROUND KAFKA LISTENER =====
    isolated function kafkaEventListener() returns error? {
        log:printInfo("Starting Kafka event listener for Transport Service");
        
        while true {
            var result = self.kafkaConsumer->poll(1000);
            if result is kafka:ConsumerRecord[] {
                foreach var record in result {
                    _ = check self.processKafkaEvent(record);
                }
                _ = check self.kafkaConsumer->commit();
            }
        }
    }

    private function processKafkaEvent(kafka:ConsumerRecord record) returns error? {
        string message = check string:fromBytes(record.value);
        json event = check value:fromJsonString(message);
        
        string eventType = event.eventType.toString();
        
        match eventType {
            "TRIP_UPDATE_CREATED" => {
                await self.handleTripUpdate(event);
            }
            "VEHICLE_LOCATION_UPDATED" => {
                await self.handleVehicleLocationUpdate(event);
            }
            _ => {
                log:printDebug("Unknown event type: " + eventType);
            }
        }
    }

    private function handleTripUpdate(json event) returns error? {
        log:printInfo("Processing trip update: " + event.message.toString());
        // Handle trip updates from admin service
        // Could update trip status, send notifications, etc.
        return;
    }

    private function handleVehicleLocationUpdate(json event) returns error? {
        log:printInfo("Processing vehicle location update for: " + event.vehicleId.toString());
        // Handle real-time vehicle location updates
        return;
    }

    // Background task for auto-completing trips
    isolated function autoCompleteTrips() returns error? {
        check self.tripManager.startAutoCompleter();
    }

    // ===== HEALTH CHECK =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/health"
    }
    resource function get health() returns string {
        return "Transport Service is healthy!";
    }

    // ===== ROUTE MANAGEMENT =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/routes"
    }
    resource function post routes(@http:Header {name: "Authorization"} string authHeader,
                                 CreateRouteRequest request) returns SuccessResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        if !isAdmin(authHeader) {
            return http:UNAUTHORIZED;
        }

        log:printInfo("Creating route: " + request.routeCode);
        
        string|error routeId = self.transportDB->createRoute(request);
        if routeId is error {
            log:printError("Route creation failed", error = routeId);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return {
            message: "Route created successfully",
            id: routeId
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/routes"
    }
    resource function get routes(@http:Header {name: "Authorization"} string authHeader) 
            returns RouteResponse[]|http:Unauthorized|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var routes = self.transportDB->getAllRoutes();
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

    // ===== VEHICLE MANAGEMENT =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/vehicles"
    }
    resource function post vehicles(@http:Header {name: "Authorization"} string authHeader,
                                   CreateVehicleRequest request) returns SuccessResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        if !isAdmin(authHeader) {
            return http:UNAUTHORIZED;
        }

        log:printInfo("Creating vehicle: " + request.vehicleNumber);
        
        string|error vehicleId = self.transportDB->createVehicle(request);
        if vehicleId is error {
            log:printError("Vehicle creation failed", error = vehicleId);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return {
            message: "Vehicle created successfully",
            id: vehicleId
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/vehicles"
    }
    resource function get vehicles(@http:Header {name: "Authorization"} string authHeader) 
            returns VehicleResponse[]|http:Unauthorized|http:InternalServerError {
        if !isAdmin(authHeader) && !isDriver(authHeader) {
            return http:UNAUTHORIZED;
        }
        
        var vehicles = self.transportDB->getAllVehicles();
        if vehicles is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var vehicle in vehicles
            select {
                id: vehicle.id.toString(),
                vehicleNumber: vehicle.vehicle_number.toString(),
                vehicleType: vehicle.vehicle_type.toString(),
                capacity: <int>vehicle.capacity,
                model: vehicle.model?.toString(),
                isActive: vehicle.is_active of boolean ? vehicle.is_active : true,
                createdAt: vehicle.created_at.toString()
            };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/vehicles/available"
    }
    resource function get vehicles/available(@http:Header {name: "Authorization"} string authHeader,
                                            string vehicleType, string date) returns VehicleResponse[]|http:Unauthorized|http:InternalServerError {
        if !isAdmin(authHeader) {
            return http:UNAUTHORIZED;
        }
        
        var vehicles = self.transportDB->getAvailableVehicles(vehicleType, date);
        if vehicles is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var vehicle in vehicles
            select {
                id: vehicle.id.toString(),
                vehicleNumber: vehicle.vehicle_number.toString(),
                vehicleType: vehicle.vehicle_type.toString(),
                capacity: <int>vehicle.capacity,
                model: vehicle.model?.toString(),
                isActive: vehicle.is_active of boolean ? vehicle.is_active : true,
                createdAt: vehicle.created_at.toString()
            };
    }

    // ===== TRIP MANAGEMENT =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/trips"
    }
    resource function post trips(@http:Header {name: "Authorization"} string authHeader,
                                CreateTripRequest request) returns SuccessResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        if !isAdmin(authHeader) {
            return http:UNAUTHORIZED;
        }

        log:printInfo("Creating trip for route: " + request.routeId);
        
        string|error tripId = self.tripManager->createTrip(request);
        if tripId is error {
            log:printError("Trip creation failed", error = tripId);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for trip creation
        _ = self.sendKafkaEvent("trip-events", {
            "eventType": "TRIP_CREATED",
            "tripId": tripId,
            "routeId": request.routeId,
            "vehicleId": request.vehicleId,
            "driverId": request.driverId,
            "scheduledDeparture": request.scheduledDeparture,
            "scheduledArrival": request.scheduledArrival,
            "basePrice": request.basePrice,
            "status": "scheduled",
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "transport-service"
        });
        
        return {
            message: "Trip created successfully",
            id: tripId
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/trips"
    }
    resource function get trips(@http:Header {name: "Authorization"} string authHeader,
                               TripSearchRequest search) returns TripDetailResponse[]|http:Unauthorized|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var trips = self.transportDB->getAllTrips(search);
        if trips is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var trip in trips
            select {
                id: trip.id.toString(),
                routeId: trip.route_id.toString(),
                vehicleId: trip.vehicle_id.toString(),
                driverId: trip.driver_id.toString(),
                scheduledDeparture: trip.scheduled_departure.toString(),
                scheduledArrival: trip.scheduled_arrival.toString(),
                actualDeparture: trip.actual_departure?.toString(),
                actualArrival: trip.actual_arrival?.toString(),
                currentLocation: trip.current_location?.toString(),
                status: trip.status.toString(),
                availableSeats: <int>trip.available_seats,
                basePrice: <decimal>trip.base_price,
                createdAt: trip.created_at.toString(),
                updatedAt: trip.updated_at.toString(),
                routeCode: trip.route_code.toString(),
                origin: trip.origin.toString(),
                destination: trip.destination.toString(),
                vehicleNumber: trip.vehicle_number.toString(),
                vehicleType: trip.vehicle_type.toString(),
                driverName: trip.driver_name.toString(),
                totalSeats: <int>trip.total_seats
            };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/trips/{tripId}"
    }
    resource function get trips/[string tripId](@http:Header {name: "Authorization"} string authHeader) 
            returns TripDetailResponse|http:Unauthorized|http:NotFound|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var trip = self.transportDB->getTrip(tripId);
        if trip is error {
            return http:NOT_FOUND;
        }
        
        return {
            id: trip.id.toString(),
            routeId: trip.route_id.toString(),
            vehicleId: trip.vehicle_id.toString(),
            driverId: trip.driver_id.toString(),
            scheduledDeparture: trip.scheduled_departure.toString(),
            scheduledArrival: trip.scheduled_arrival.toString(),
            actualDeparture: trip.actual_departure?.toString(),
            actualArrival: trip.actual_arrival?.toString(),
            currentLocation: trip.current_location?.toString(),
            status: trip.status.toString(),
            availableSeats: <int>trip.available_seats,
            basePrice: <decimal>trip.base_price,
            createdAt: trip.created_at.toString(),
            updatedAt: trip.updated_at.toString(),
            routeCode: trip.route_code.toString(),
            origin: trip.origin.toString(),
            destination: trip.destination.toString(),
            vehicleNumber: trip.vehicle_number.toString(),
            vehicleType: trip.vehicle_type.toString(),
            driverName: trip.driver_name.toString(),
            totalSeats: <int>trip.total_seats
        };
    }

    // ===== DRIVER ENDPOINTS WITH KAFKA =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/driver/trips"
    }
    resource function get driver/trips(@http:Header {name: "Authorization"} string authHeader,
                                      string? date) returns TripDetailResponse[]|http:Unauthorized|http:InternalServerError {
        if !isDriver(authHeader) {
            return http:UNAUTHORIZED;
        }
        
        string driverId = validateAuth(authHeader);
        
        var trips = self.transportDB->getDriverTrips(driverId, date);
        if trips is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var trip in trips
            select {
                id: trip.id.toString(),
                routeId: trip.route_id.toString(),
                vehicleId: trip.vehicle_id.toString(),
                driverId: trip.driver_id.toString(),
                scheduledDeparture: trip.scheduled_departure.toString(),
                scheduledArrival: trip.scheduled_arrival.toString(),
                actualDeparture: trip.actual_departure?.toString(),
                actualArrival: trip.actual_arrival?.toString(),
                currentLocation: trip.current_location?.toString(),
                status: trip.status.toString(),
                availableSeats: <int>trip.available_seats,
                basePrice: <decimal>trip.base_price,
                createdAt: trip.created_at.toString(),
                updatedAt: trip.updated_at.toString(),
                routeCode: trip.route_code.toString(),
                origin: trip.origin.toString(),
                destination: trip.destination.toString(),
                vehicleNumber: trip.vehicle_number.toString(),
                vehicleType: trip.vehicle_type.toString(),
                driverName: trip.driver_name?.toString() ?: "Unknown Driver",
                totalSeats: <int>trip.total_seats
            };
    }

    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/driver/trips/{tripId}/status"
    }
    resource function put driver/trips/[string tripId]/status(@http:Header {name: "Authorization"} string authHeader,
                                                             string status, string? currentLocation) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        if !isDriver(authHeader) {
            return http:UNAUTHORIZED;
        }
        
        var result = self.tripManager->updateTripStatus(tripId, status, currentLocation);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for trip status update
        _ = self.sendKafkaEvent("trip-events", {
            "eventType": "TRIP_STATUS_UPDATED",
            "tripId": tripId,
            "status": status,
            "currentLocation": currentLocation,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "transport-service"
        });

        return {
            message: "Trip status updated successfully"
        };
    }

    @http:ResourceConfig {
        methods: ["PUT"],
        path: "/driver/vehicles/{vehicleId}/location"
    }
    resource function put driver/vehicles/[string vehicleId]/location(@http:Header {name: "Authorization"} string authHeader,
                                                                     string currentLocation, decimal? latitude, decimal? longitude) returns SuccessResponse|http:Unauthorized|http:InternalServerError {
        if !isDriver(authHeader) {
            return http:UNAUTHORIZED;
        }
        
        var result = self.tripManager->updateVehicleLocation(vehicleId, currentLocation, latitude, longitude);
        if result is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        // Send Kafka event for vehicle location update
        _ = self.sendKafkaEvent("vehicle-updates", {
            "eventType": "VEHICLE_LOCATION_UPDATED",
            "vehicleId": vehicleId,
            "currentLocation": currentLocation,
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "transport-service"
        });

        return {
            message: "Vehicle location updated successfully"
        };
    }

    // ===== SCHEDULE MANAGEMENT =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/schedules"
    }
    resource function post schedules(@http:Header {name: "Authorization"} string authHeader,
                                    ScheduleRequest request) returns ScheduleResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        if !isAdmin(authHeader) {
            return http:UNAUTHORIZED;
        }

        log:printInfo("Creating schedule for route: " + request.routeId);
        
        string[]|error tripIds = self.tripManager->createSchedule(request);
        if tripIds is error {
            log:printError("Schedule creation failed", error = tripIds);
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return {
            message: "Schedule created successfully",
            tripsCreated: tripIds.length(),
            tripIds: tripIds
        };
    }

    // ===== STATISTICS =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/stats"
    }
    resource function get stats(@http:Header {name: "Authorization"} string authHeader) returns StatsResponse|http:Unauthorized|http:InternalServerError {
        if !isAdmin(authHeader) {
            return http:UNAUTHORIZED;
        }
        
        var stats = self.transportDB->getTransportStats();
        if stats is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return {
            totalRoutes: <int>stats.total_routes,
            activeTrips: <int>stats.active_trips,
            totalVehicles: <int>stats.total_vehicles,
            availableVehicles: <int>stats.available_vehicles,
            scheduledTripsToday: <int>stats.scheduled_trips_today
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