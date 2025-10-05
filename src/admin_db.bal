import ballerinax/postgresql;
import ballerina/sql;
import ballerina/crypto;

// Helper function to extract generated keys
function extractGeneratedKey(stream<record {}, error?> resultStream) returns string|error {
    record {|string id;|}[] result = check resultStream.toArray();
    if result.length() > 0 {
        return result[0].id;
    }
    return error("No ID returned from query");
}

public isolated client class AdminDBClient {
    private final postgresql:Client dbClient;

    public function init(postgresql:Client dbClient) {
        self.dbClient = dbClient;
    }

    // ===== USER MANAGEMENT =====
    public function createUser(CreateUserRequest user) returns string|error {
        string query = `INSERT INTO users (email, password_hash, first_name, last_name, role, phone_number) 
                        VALUES ($1, $2, $3, $4, $5::user_role, $6) RETURNING id`;
        
        // Simple hashing for demo - in production use bcrypt
        string passwordHash = crypto:hashSha256(user.password.toBytes()).toBase16();
        
        var result = self.dbClient->query(query, user.email, passwordHash, user.firstName, 
                                         user.lastName, user.role, user.phoneNumber);
        return extractGeneratedKey(result);
    }

    public function getAllUsers(string? role) returns map<anydata>[]|error {
        string baseQuery = `SELECT id, email, first_name, last_name, role, phone_number, 
                        is_active, created_at, updated_at
                        FROM users`;
        
        if role is () {
            return self.dbClient->query(baseQuery + " ORDER BY created_at DESC");
        } else {
            return self.dbClient->query(baseQuery + " WHERE role = $1::user_role ORDER BY created_at DESC", role);
        }
    }

    public function getUserById(string userId) returns map<anydata>|error {
        string query = `SELECT id, email, first_name, last_name, role, phone_number, 
                    is_active, created_at, updated_at
                    FROM users WHERE id = $1`;
        
        var result = self.dbClient->query(query, userId);
        if result is map<anydata>[] && result.length() > 0 {
            return result[0];
        }
        return error("User not found");
    }

    public function updateUser(string userId, UpdateUserRequest user) returns error? {
        sql:ParameterizedQuery query = `UPDATE users SET updated_at = CURRENT_TIMESTAMP`;
        sql:ParameterizedQuery[] params = [];
        int paramCount = 0;
        
        if user.email is string {
            paramCount += 1;
            query = query + `, email = $${paramCount.toString()}`;
            params.push(user.email);
        }
        
        if user.firstName is string {
            paramCount += 1;
            query = query + `, first_name = $${paramCount.toString()}`;
            params.push(user.firstName);
        }
        
        if user.lastName is string {
            paramCount += 1;
            query = query + `, last_name = $${paramCount.toString()}`;
            params.push(user.lastName);
        }
        
        if user.phoneNumber is string {
            paramCount += 1;
            query = query + `, phone_number = $${paramCount.toString()}`;
            params.push(user.phoneNumber);
        } else if user.phoneNumber is () {
            paramCount += 1;
            query = query + `, phone_number = $${paramCount.toString()}`;
            params.push(null);
        }
        
        if user.isActive is boolean {
            paramCount += 1;
            query = query + `, is_active = $${paramCount.toString()}`;
            params.push(user.isActive);
        }
        
        paramCount += 1;
        query = query + ` WHERE id = $${paramCount.toString()}`;
        params.push(userId);
        
        _ = check self.dbClient->execute(query, ...params);
    }

    public function deleteUser(string userId) returns error? {
        string query = `UPDATE users SET is_active = false, updated_at = CURRENT_TIMESTAMP 
                    WHERE id = $1`;
        _ = check self.dbClient->execute(query, userId);
    }

    public function changeUserRole(string userId, string newRole) returns error? {
        string query = `UPDATE users SET role = $1::user_role, updated_at = CURRENT_TIMESTAMP 
                    WHERE id = $2`;
        _ = check self.dbClient->execute(query, newRole, userId);
    }

    // ===== ROUTE MANAGEMENT =====
    public function createRoute(CreateRouteRequest route) returns string|error {
        string query = `INSERT INTO routes (route_code, origin, destination, distance_km, estimated_duration_minutes) 
                        VALUES ($1, $2, $3, $4, $5) RETURNING id`;
        var result = self.dbClient->query(query, route.routeCode, route.origin, 
                                         route.destination, route.distanceKm, 
                                         route.estimatedDurationMinutes);
        return extractGeneratedKey(result);
    }

    public function getAllRoutes() returns map<anydata>[]|error {
        string query = `SELECT id, route_code, origin, destination, distance_km, 
                        estimated_duration_minutes, is_active, created_at
                        FROM routes 
                        ORDER BY created_at DESC`;
        return self.dbClient->query(query);
    }

    public function updateRouteStatus(string routeId, boolean isActive) returns error? {
        string query = `UPDATE routes SET is_active = $1 WHERE id = $2`;
        _ = check self.dbClient->execute(query, isActive, routeId);
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
        return extractGeneratedKey(result);
    }

    public function getAllTrips(string? status) returns map<anydata>[]|error {
        string baseQuery = `SELECT t.*, r.route_code, r.origin, r.destination,
                           v.vehicle_number, v.vehicle_type,
                           u.first_name || ' ' || u.last_name as driver_name
                           FROM trips t
                           JOIN routes r ON t.route_id = r.id
                           JOIN vehicles v ON t.vehicle_id = v.id
                           JOIN users u ON t.driver_id = u.id`;
        
        if status is () {
            return self.dbClient->query(baseQuery + " ORDER BY t.scheduled_departure DESC");
        } else {
            return self.dbClient->query(baseQuery + " WHERE t.status = $1 ORDER BY t.scheduled_departure DESC", status);
        }
    }

    public function updateTripStatus(string tripId, string status) returns error? {
        string query = `UPDATE trips SET status = $1, updated_at = CURRENT_TIMESTAMP 
                        WHERE id = $2`;
        _ = check self.dbClient->execute(query, status, tripId);
    }

    public function cancelTrip(string tripId, string reason) returns error? {
        string query = `UPDATE trips SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP 
                        WHERE id = $1`;
        _ = check self.dbClient->execute(query, tripId);
        
        // Log cancellation reason
        string logQuery = `INSERT INTO trip_updates (trip_id, update_type, message, created_by)
                          VALUES ($1, 'cancellation', $2, 'admin')`;
        _ = check self.dbClient->execute(logQuery, tripId, reason);
    }

    // ===== REPORTING & ANALYTICS =====
    public function getSalesReport(string startDate, string endDate, string? ticketType) returns map<anydata>[]|error {
        string baseQuery = `SELECT sale_date, ticket_type, hour_slot, amount_sold, tickets_count
                           FROM ticket_sales_daily
                           WHERE sale_date BETWEEN $1 AND $2`;
        
        if ticketType is () {
            return self.dbClient->query(baseQuery + " ORDER BY sale_date, hour_slot", startDate, endDate);
        } else {
            return self.dbClient->query(baseQuery + " AND ticket_type = $3 ORDER BY sale_date, hour_slot", 
                                       startDate, endDate, ticketType);
        }
    }

    public function getSystemStats() returns map<anydata>|error {
        string query = `SELECT 
            (SELECT COUNT(*) FROM users) as total_users,
            (SELECT COUNT(*) FROM trips WHERE status IN ('scheduled', 'boarding', 'in_progress')) as active_trips,
            (SELECT COUNT(*) FROM tickets WHERE DATE(created_at) = CURRENT_DATE) as tickets_sold_today,
            (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE DATE(created_at) = CURRENT_DATE AND status = 'completed') as revenue_today,
            (SELECT COUNT(*) FROM routes WHERE is_active = true) as total_routes,
            (SELECT COUNT(*) FROM vehicles WHERE is_active = true) as active_vehicles`;
        
        var result = self.dbClient->query(query);
        if result is map<anydata>[] && result.length() > 0 {
            return result[0];
        }
        return error("Failed to get system stats");
    }

    public function getPassengerTraffic(string startDate, string endDate) returns map<anydata>[]|error {
        string query = `SELECT 
            DATE(t.created_at) as travel_date,
            COUNT(*) as passenger_count,
            COUNT(DISTINCT t.passenger_id) as unique_passengers
            FROM tickets t
            WHERE DATE(t.created_at) BETWEEN $1 AND $2
            AND t.status IN ('paid', 'validated')
            GROUP BY DATE(t.created_at)
            ORDER BY travel_date`;
        
        return self.dbClient->query(query, startDate, endDate);
    }

    // ===== SERVICE DISRUPTIONS =====
    public function createTripUpdate(TripUpdateRequest update, string adminId) returns error? {
        string query = `INSERT INTO trip_updates (trip_id, update_type, message, delay_minutes, 
                        new_departure_time, new_arrival_time, created_by)
                        VALUES ($1, $2, $3, $4, $5::timestamp, $6::timestamp, $7)`;
        _ = check self.dbClient->execute(query, update.tripId, update.updateType, update.message,
                                        update.delayMinutes, update.newDepartureTime,
                                        update.newArrivalTime, adminId);
    }
}