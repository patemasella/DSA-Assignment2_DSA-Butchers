import ballerinax/postgresql;
import ballerina/log;

public isolated client class TransportDBClient {
    private final postgresql:Client dbClient;

    public function init(postgresql:Client dbClient) {
        self.dbClient = dbClient;
    }

    // ===== ROUTE MANAGEMENT =====
    public function createRoute(CreateRouteRequest route) returns string|error {
        string query = `INSERT INTO routes (route_code, origin, destination, distance_km, estimated_duration_minutes) 
                        VALUES ($1, $2, $3, $4, $5) RETURNING id`;
        
        var result = self.dbClient->query(query, route.routeCode, route.origin, 
                                         route.destination, route.distanceKm, 
                                         route.estimatedDurationMinutes);
        
        record {|string id;|}[] rows = check result.toArray();
        if rows.length() == 0 {
            return error("Failed to create route");
        }
        return rows[0].id;
    }

    public function getAllRoutes() returns map<anydata>[]|error {
        string query = `SELECT id, route_code, origin, destination, distance_km, 
                        estimated_duration_minutes, is_active, created_at
                        FROM routes 
                        ORDER BY route_code`;
        return self.dbClient->query(query);
    }

    public function getRoute(string routeId) returns map<anydata>|error {
        string query = `SELECT id, route_code, origin, destination, distance_km, 
                        estimated_duration_minutes, is_active, created_at
                        FROM routes WHERE id = $1`;
        
        var result = self.dbClient->query(query, routeId);
        record {|string id; string route_code; string origin; string destination; decimal distance_km; int estimated_duration_minutes; boolean is_active; string created_at;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Route not found");
        }
        return rows[0];
    }

    public function updateRoute(string routeId, UpdateRouteRequest update) returns error? {
        sql:ParameterizedQuery query = `UPDATE routes SET updated_at = CURRENT_TIMESTAMP`;
        string[] params = [];
        int paramCount = 0;
        
        if update.origin is string {
            paramCount += 1;
            query = query + `, origin = $${paramCount.toString()}`;
            params.push(update.origin);
        }
        
        if update.destination is string {
            paramCount += 1;
            query = query + `, destination = $${paramCount.toString()}`;
            params.push(update.destination);
        }
        
        if update.distanceKm is decimal {
            paramCount += 1;
            query = query + `, distance_km = $${paramCount.toString()}`;
            params.push(update.distanceKm);
        }
        
        if update.estimatedDurationMinutes is int {
            paramCount += 1;
            query = query + `, estimated_duration_minutes = $${paramCount.toString()}`;
            params.push(update.estimatedDurationMinutes);
        }
        
        if update.isActive is boolean {
            paramCount += 1;
            query = query + `, is_active = $${paramCount.toString()}`;
            params.push(update.isActive);
        }
        
        paramCount += 1;
        query = query + ` WHERE id = $${paramCount.toString()}`;
        params.push(routeId);
        
        _ = check self.dbClient->execute(query, ...params);
    }

    // ===== VEHICLE MANAGEMENT =====
    public function createVehicle(CreateVehicleRequest vehicle) returns string|error {
        string query = `INSERT INTO vehicles (vehicle_number, vehicle_type, capacity, model) 
                        VALUES ($1, $2::vehicle_type, $3, $4) RETURNING id`;
        
        var result = self.dbClient->query(query, vehicle.vehicleNumber, vehicle.vehicleType, 
                                         vehicle.capacity, vehicle.model);
        
        record {|string id;|}[] rows = check result.toArray();
        if rows.length() == 0 {
            return error("Failed to create vehicle");
        }
        return rows[0].id;
    }

    public function getAllVehicles() returns map<anydata>[]|error {
        string query = `SELECT id, vehicle_number, vehicle_type, capacity, model, is_active, created_at
                        FROM vehicles 
                        ORDER BY vehicle_number`;
        return self.dbClient->query(query);
    }

    public function getAvailableVehicles(string vehicleType, string date) returns map<anydata>[]|error {
        string query = `SELECT v.*
                        FROM vehicles v
                        WHERE v.vehicle_type = $1::vehicle_type 
                        AND v.is_active = true
                        AND NOT EXISTS (
                            SELECT 1 FROM trips t 
                            WHERE t.vehicle_id = v.id 
                            AND DATE(t.scheduled_departure) = $2::date
                            AND t.status IN ('scheduled', 'boarding', 'in_progress')
                        )
                        ORDER BY v.vehicle_number`;
        
        return self.dbClient->query(query, vehicleType, date);
    }

    public function updateVehicle(string vehicleId, UpdateVehicleRequest update) returns error? {
        sql:ParameterizedQuery query = `UPDATE vehicles SET updated_at = CURRENT_TIMESTAMP`;
        string[] params = [];
        int paramCount = 0;
        
        if update.vehicleNumber is string {
            paramCount += 1;
            query = query + `, vehicle_number = $${paramCount.toString()}`;
            params.push(update.vehicleNumber);
        }
        
        if update.vehicleType is string {
            paramCount += 1;
            query = query + `, vehicle_type = $${paramCount.toString()}::vehicle_type`;
            params.push(update.vehicleType);
        }
        
        if update.capacity is int {
            paramCount += 1;
            query = query + `, capacity = $${paramCount.toString()}`;
            params.push(update.capacity);
        }
        
        if update.model is string {
            paramCount += 1;
            query = query + `, model = $${paramCount.toString()}`;
            params.push(update.model);
        }
        
        if update.isActive is boolean {
            paramCount += 1;
            query = query + `, is_active = $${paramCount.toString()}`;
            params.push(update.isActive);
        }
        
        paramCount += 1;
        query = query + ` WHERE id = $${paramCount.toString()}`;
        params.push(vehicleId);
        
        _ = check self.dbClient->execute(query, ...params);
    }

    // ===== TRIP MANAGEMENT =====
    public function createTrip(CreateTripRequest trip) returns string|error {
        string query = `INSERT INTO trips (route_id, vehicle_id, driver_id, scheduled_departure, 
                        scheduled_arrival, available_seats, base_price)
                        VALUES ($1, $2, $3, $4::timestamp, $5::timestamp, 
                        (SELECT capacity FROM vehicles WHERE id = $2), $6)
                        RETURNING id`;
        
        var result = self.dbClient->query(query, trip.routeId, trip.vehicleId, 
                                         trip.driverId, trip.scheduledDeparture,
                                         trip.scheduledArrival, trip.basePrice);
        
        record {|string id;|}[] rows = check result.toArray();
        if rows.length() == 0 {
            return error("Failed to create trip");
        }
        return rows[0].id;
    }

    public function getTrip(string tripId) returns map<anydata>|error {
        string query = `SELECT 
            t.*,
            r.route_code, r.origin, r.destination,
            v.vehicle_number, v.vehicle_type, v.capacity as total_seats,
            u.first_name || ' ' || u.last_name as driver_name
            FROM trips t
            JOIN routes r ON t.route_id = r.id
            JOIN vehicles v ON t.vehicle_id = v.id
            JOIN users u ON t.driver_id = u.id
            WHERE t.id = $1`;
        
        var result = self.dbClient->query(query, tripId);
        record {|string id; string route_id; string vehicle_id; string driver_id; string scheduled_departure; string scheduled_arrival; string actual_departure; string actual_arrival; string current_location; string status; int available_seats; decimal base_price; string created_at; string updated_at; string route_code; string origin; string destination; string vehicle_number; string vehicle_type; int total_seats; string driver_name;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Trip not found");
        }
        return rows[0];
    }

    public function getAllTrips(TripSearchRequest search) returns map<anydata>[]|error {
        string baseQuery = `SELECT 
            t.*,
            r.route_code, r.origin, r.destination,
            v.vehicle_number, v.vehicle_type,
            u.first_name || ' ' || u.last_name as driver_name
            FROM trips t
            JOIN routes r ON t.route_id = r.id
            JOIN vehicles v ON t.vehicle_id = v.id
            JOIN users u ON t.driver_id = u.id
            WHERE 1=1`;
        
        string[] params = [];
        int paramCount = 0;

        if search.routeId is string {
            paramCount += 1;
            baseQuery += ` AND t.route_id = $${paramCount.toString()}`;
            params.push(search.routeId);
        }

        if search.vehicleId is string {
            paramCount += 1;
            baseQuery += ` AND t.vehicle_id = $${paramCount.toString()}`;
            params.push(search.vehicleId);
        }

        if search.driverId is string {
            paramCount += 1;
            baseQuery += ` AND t.driver_id = $${paramCount.toString()}`;
            params.push(search.driverId);
        }

        if search.status is string {
            paramCount += 1;
            baseQuery += ` AND t.status = $${paramCount.toString()}`;
            params.push(search.status);
        }

        if search.dateFrom is string {
            paramCount += 1;
            baseQuery += ` AND DATE(t.scheduled_departure) >= $${paramCount.toString()}`;
            params.push(search.dateFrom);
        }

        if search.dateTo is string {
            paramCount += 1;
            baseQuery += ` AND DATE(t.scheduled_departure) <= $${paramCount.toString()}`;
            params.push(search.dateTo);
        }

        baseQuery += " ORDER BY t.scheduled_departure DESC";

        return self.dbClient->query(baseQuery, ...params);
    }

    public function updateTrip(string tripId, TripUpdateRequest update) returns error? {
        sql:ParameterizedQuery query = `UPDATE trips SET updated_at = CURRENT_TIMESTAMP`;
        string[] params = [];
        int paramCount = 0;
        
        if update.currentLocation is string {
            paramCount += 1;
            query = query + `, current_location = $${paramCount.toString()}`;
            params.push(update.currentLocation);
        }
        
        if update.status is string {
            paramCount += 1;
            query = query + `, status = $${paramCount.toString()}::trip_status`;
            params.push(update.status);
            
            // Set actual departure/arrival times based on status
            if update.status == "in_progress" {
                paramCount += 1;
                query = query + `, actual_departure = $${paramCount.toString()}`;
                params.push("CURRENT_TIMESTAMP");
            } else if update.status == "completed" {
                paramCount += 1;
                query = query + `, actual_arrival = $${paramCount.toString()}`;
                params.push("CURRENT_TIMESTAMP");
            }
        }
        
        if update.actualDeparture is string {
            paramCount += 1;
            query = query + `, actual_departure = $${paramCount.toString()}::timestamp`;
            params.push(update.actualDeparture);
        }
        
        if update.actualArrival is string {
            paramCount += 1;
            query = query + `, actual_arrival = $${paramCount.toString()}::timestamp`;
            params.push(update.actualArrival);
        }
        
        paramCount += 1;
        query = query + ` WHERE id = $${paramCount.toString()}`;
        params.push(tripId);
        
        _ = check self.dbClient->execute(query, ...params);
    }

    public function getDriverTrips(string driverId, string? date) returns map<anydata>[]|error {
        string baseQuery = `SELECT 
            t.*,
            r.route_code, r.origin, r.destination,
            v.vehicle_number, v.vehicle_type
            FROM trips t
            JOIN routes r ON t.route_id = r.id
            JOIN vehicles v ON t.vehicle_id = v.id
            WHERE t.driver_id = $1`;
        
        if date is string {
            return self.dbClient->query(baseQuery + " AND DATE(t.scheduled_departure) = $2 ORDER BY t.scheduled_departure", driverId, date);
        } else {
            return self.dbClient->query(baseQuery + " ORDER BY t.scheduled_departure DESC", driverId);
        }
    }

    // ===== SCHEDULE MANAGEMENT =====
    public function createBulkTrips(CreateTripRequest[] trips) returns string[]|error {
        string[] tripIds = [];
        
        foreach var trip in trips {
            string|error tripId = self.createTrip(trip);
            if tripId is error {
                log:printError("Failed to create trip in bulk", error = tripId);
            } else {
                tripIds.push(tripId);
            }
        }
        
        return tripIds;
    }

    // ===== STATISTICS =====
    public function getTransportStats() returns map<anydata>|error {
        string query = `SELECT 
            (SELECT COUNT(*) FROM routes WHERE is_active = true) as total_routes,
            (SELECT COUNT(*) FROM trips WHERE status IN ('scheduled', 'boarding', 'in_progress')) as active_trips,
            (SELECT COUNT(*) FROM vehicles WHERE is_active = true) as total_vehicles,
            (SELECT COUNT(*) FROM vehicles WHERE is_active = true AND id NOT IN (
                SELECT DISTINCT vehicle_id FROM trips 
                WHERE DATE(scheduled_departure) = CURRENT_DATE 
                AND status IN ('scheduled', 'boarding', 'in_progress')
            )) as available_vehicles,
            (SELECT COUNT(*) FROM trips WHERE DATE(scheduled_departure) = CURRENT_DATE) as scheduled_trips_today`;
        
        var result = self.dbClient->query(query);
        record {|int total_routes; int active_trips; int total_vehicles; int available_vehicles; int scheduled_trips_today;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Failed to get transport stats");
        }
        return rows[0];
    }
}