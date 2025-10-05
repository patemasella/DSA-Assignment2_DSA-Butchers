import ballerinax/kafka;
import ballerina/log;
import ballerina/lang.'value;
import ballerina/time;

configurable string kafkaBootstrapServers = "localhost:9092";
configurable string tripEventsTopic = "trip-events";
configurable string vehicleUpdatesTopic = "vehicle-updates";

configurable int autoCompleteDelay = 3600; // 1 hour in seconds

public isolated client class TripManager {
    private final kafka:Producer kafkaProducer;
    private final TransportDBClient transportDB;

    public function init(TransportDBClient transportDB) returns error? {
        self.kafkaProducer = check new (kafkaBootstrapServers);
        self.transportDB = transportDB;
        log:printInfo("Trip manager initialized");
    }

    // ===== TRIP LIFECYCLE MANAGEMENT =====
    public function createTrip(CreateTripRequest trip) returns string|error {
        log:printInfo("Creating trip for route: " + trip.routeId);
        
        string tripId = check self.transportDB->createTrip(trip);
        
        // Send trip creation event
        check self.sendTripEvent({
            eventType: "TRIP_CREATED",
            tripId: tripId,
            routeId: trip.routeId,
            vehicleId: trip.vehicleId,
            driverId: trip.driverId,
            status: "scheduled",
            currentLocation: (),
            timestamp: self.getCurrentTimestamp()
        });
        
        return tripId;
    }

    public function updateTripStatus(string tripId, string status, string? currentLocation) returns error? {
        log:printInfo("Updating trip " + tripId + " status to: " + status);
        
        var updateResult = self.transportDB->updateTrip(tripId, {
            status: status,
            currentLocation: currentLocation
        });
        
        if updateResult is error {
            return updateResult;
        }
        
        // Send trip status update event
        check self.sendTripEvent({
            eventType: "TRIP_STATUS_UPDATED",
            tripId: tripId,
            routeId: "", // Would get from trip
            vehicleId: "", // Would get from trip
            driverId: "", // Would get from trip
            status: status,
            currentLocation: currentLocation,
            timestamp: self.getCurrentTimestamp()
        });
        
        return;
    }

    public function updateVehicleLocation(string vehicleId, string currentLocation, decimal? latitude, decimal? longitude) returns error? {
        log:printInfo("Updating vehicle " + vehicleId + " location to: " + currentLocation);
        
        // Send vehicle location update event
        check self.sendVehicleEvent({
            eventType: "VEHICLE_LOCATION_UPDATED",
            vehicleId: vehicleId,
            vehicleNumber: "", // Would get from vehicle
            currentLocation: currentLocation,
            status: "in_service",
            timestamp: self.getCurrentTimestamp()
        });
        
        return;
    }

    // ===== SCHEDULE MANAGEMENT =====
    public function createSchedule(ScheduleRequest schedule) returns string[]|error {
        log:printInfo("Creating schedule for route: " + schedule.routeId);
        
        CreateTripRequest[] trips = [];
        
        // Parse start and end dates
        time:Date startDate = check time:dateFromString(schedule.startDate);
        time:Date endDate = check time:dateFromString(schedule.endDate);
        
        // Generate trips for each day in the range
        time:Date currentDate = startDate;
        while currentDate <= endDate {
            foreach string timeStr in schedule.times {
                time:Time time = check time:timeFromString(timeStr + ":00");
                time:Civil scheduledDeparture = {
                    year: currentDate.year,
                    month: currentDate.month,
                    day: currentDate.day,
                    hour: time.hour,
                    minute: time.minute,
                    second: time.second
                };
                
                // Calculate arrival time (add estimated duration)
                // For demo, add 1 hour to departure time
                time:Civil scheduledArrival = scheduledDeparture;
                scheduledArrival = scheduledArrival.addHours(1);
                
                trips.push({
                    routeId: schedule.routeId,
                    vehicleId: schedule.vehicleId,
                    driverId: schedule.driverId,
                    scheduledDeparture: scheduledDeparture.toString(),
                    scheduledArrival: scheduledArrival.toString(),
                    basePrice: schedule.basePrice
                });
            }
            
            currentDate = currentDate.addDays(1);
        }
        
        string[] tripIds = check self.transportDB->createBulkTrips(trips);
        
        log:printInfo("Created " + tripIds.length().toString() + " scheduled trips");
        return tripIds;
    }

    // ===== AUTOMATIC TRIP COMPLETION =====
    public function startAutoCompleter() returns error? {
        log:printInfo("Starting auto-complete service for trips");
        
        while true {
            _ = check self.completeOverdueTrips();
            // Check every 5 minutes
            runtime:sleep(300000);
        }
    }

    private function completeOverdueTrips() returns error? {
        // Find trips that should be auto-completed
        string query = `SELECT id FROM trips 
                        WHERE status = 'in_progress' 
                        AND scheduled_arrival < (CURRENT_TIMESTAMP - INTERVAL '1 hour')
                        AND actual_arrival IS NULL`;
        
        var result = self.transportDB.dbClient->query(query);
        record {|string id;|}[] rows = check result.toArray();
        
        foreach var row in rows {
            log:printInfo("Auto-completing overdue trip: " + row.id.toString());
            _ = check self.updateTripStatus(row.id.toString(), "completed", ());
        }
        
        if rows.length() > 0 {
            log:printInfo("Auto-completed " + rows.length().toString() + " trips");
        }
        
        return;
    }

    // ===== PRIVATE METHODS =====
    private function getCurrentTimestamp() returns string {
        return string `${{time:utcNow().format("yyyy-MM-dd'T'HH:mm:ss'Z'")}}`;
    }

    private function sendTripEvent(TripEvent event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        check self.kafkaProducer->send({
            topic: tripEventsTopic,
            value: eventJson.toBytes()
        });
        log:printInfo("Sent trip event: " + event.eventType);
    }

    private function sendVehicleEvent(VehicleEvent event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        check self.kafkaProducer->send({
            topic: vehicleUpdatesTopic,
            value: eventJson.toBytes()
        });
        log:printInfo("Sent vehicle event: " + event.eventType);
    }

    public function close() returns error? {
        return self.kafkaProducer->close();
    }
}