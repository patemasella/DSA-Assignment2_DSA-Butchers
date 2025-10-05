import ballerinax/postgresql;
import ballerina/crypto;
import ballerina/log;

public isolated client class PassengerDBClient {
    private final postgresql:Client dbClient;

    public function init(postgresql:Client dbClient) {
        self.dbClient = dbClient;
    }

    // ===== AUTHENTICATION =====
    public function registerPassenger(PassengerRegisterRequest passenger) returns string|error {
        string query = `INSERT INTO users (email, password_hash, first_name, last_name, role, phone_number) 
                        VALUES ($1, $2, $3, $4, 'passenger', $5) RETURNING id`;
        
        // Simple password hashing for demo
        string passwordHash = crypto:hashSha256(passenger.password.toBytes()).toBase16();
        
        var result = self.dbClient->query(query, passenger.email, passwordHash, 
                                         passenger.firstName, passenger.lastName, 
                                         passenger.phoneNumber);
        
        record {|string id;|}[] rows = check result.toArray();
        if rows.length() == 0 {
            return error("Failed to create passenger");
        }
        return rows[0].id;
    }

    public function validatePassengerCredentials(string email, string password) returns string|error {
        string query = `SELECT id, password_hash FROM users 
                        WHERE email = $1 AND role = 'passenger' AND is_active = true`;
        
        var result = self.dbClient->query(query, email);
        record {|string id; string password_hash;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Invalid email or password");
        }
        
        string hashedPassword = crypto:hashSha256(password.toBytes()).toBase16();
        if rows[0].password_hash != hashedPassword {
            return error("Invalid email or password");
        }
        
        return rows[0].id;
    }

    // ===== TRIP SEARCH =====
    public function searchAvailableTrips(TripSearchRequest search) returns map<anydata>[]|error {
        string query = `SELECT 
            t.id as trip_id,
            r.id as route_id,
            r.origin,
            r.destination,
            t.scheduled_departure,
            t.scheduled_arrival,
            v.vehicle_number,
            v.vehicle_type,
            u.first_name || ' ' || u.last_name as driver_name,
            t.available_seats,
            t.base_price,
            t.status
            FROM trips t
            JOIN routes r ON t.route_id = r.id
            JOIN vehicles v ON t.vehicle_id = v.id
            JOIN users u ON t.driver_id = u.id
            WHERE r.origin = $1 
            AND r.destination = $2
            AND DATE(t.scheduled_departure) = $3::date
            AND t.status = 'scheduled'
            AND t.available_seats > 0
            ORDER BY t.scheduled_departure`;
        
        return self.dbClient->query(query, search.origin, search.destination, search.date);
    }

    // ===== TICKET MANAGEMENT =====
    public function createTicket(string passengerId, string tripId, string ticketType, decimal price) returns string|error {
        string query = `INSERT INTO tickets (passenger_id, trip_id, ticket_type, purchase_price, valid_from, valid_until)
                        VALUES ($1, $2, $3::ticket_type, $4, 
                        (SELECT scheduled_departure FROM trips WHERE id = $2),
                        (SELECT scheduled_arrival FROM trips WHERE id = $2))
                        RETURNING id`;
        
        var result = self.dbClient->query(query, passengerId, tripId, ticketType, price);
        record {|string id;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Failed to create ticket");
        }
        return rows[0].id;
    }

    public function getPassengerTickets(string passengerId) returns map<anydata>[]|error {
        string query = `SELECT 
            t.id as ticket_id,
            t.ticket_type,
            t.status,
            t.purchase_price,
            t.valid_from,
            t.valid_until,
            t.created_at,
            tr.scheduled_departure,
            r.origin,
            r.destination,
            v.vehicle_number
            FROM tickets t
            JOIN trips tr ON t.trip_id = tr.id
            JOIN routes r ON tr.route_id = r.id
            JOIN vehicles v ON tr.vehicle_id = v.id
            WHERE t.passenger_id = $1
            ORDER BY t.created_at DESC`;
        
        return self.dbClient->query(query, passengerId);
    }

    public function validateTicket(string ticketId, string passengerId) returns boolean|error {
        string query = `UPDATE tickets 
                        SET status = 'validated', boarding_time = CURRENT_TIMESTAMP
                        WHERE id = $1 AND passenger_id = $2 
                        AND status = 'paid'
                        AND valid_until > CURRENT_TIMESTAMP
                        RETURNING id`;
        
        var result = self.dbClient->query(query, ticketId, passengerId);
        record {|string id;|}[] rows = check result.toArray();
        
        return rows.length() > 0;
    }

    // ===== PROFILE MANAGEMENT =====
    public function getPassengerProfile(string passengerId) returns map<anydata>|error {
        string query = `SELECT id, email, first_name, last_name, phone_number, is_active, created_at
                        FROM users WHERE id = $1 AND role = 'passenger'`;
        
        var result = self.dbClient->query(query, passengerId);
        record {|string id; string email; string first_name; string last_name; string phone_number; boolean is_active; string created_at;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Passenger not found");
        }
        return rows[0];
    }

    public function updatePassengerProfile(string passengerId, string? firstName, string? lastName, string? phoneNumber) returns error? {
        sql:ParameterizedQuery query = `UPDATE users SET updated_at = CURRENT_TIMESTAMP`;
        string[] params = [];
        int paramCount = 0;
        
        if firstName is string {
            paramCount += 1;
            query = query + `, first_name = $${paramCount.toString()}`;
            params.push(firstName);
        }
        
        if lastName is string {
            paramCount += 1;
            query = query + `, last_name = $${paramCount.toString()}`;
            params.push(lastName);
        }
        
        if phoneNumber is string {
            paramCount += 1;
            query = query + `, phone_number = $${paramCount.toString()}`;
            params.push(phoneNumber);
        } else if phoneNumber is () {
            paramCount += 1;
            query = query + `, phone_number = $${paramCount.toString()}`;
            params.push("");
        }
        
        paramCount += 1;
        query = query + ` WHERE id = $${paramCount.toString()}`;
        params.push(passengerId);
        
        _ = check self.dbClient->execute(query, ...params);
    }
}