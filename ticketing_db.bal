import ballerinax/postgresql;
import ballerina/log;

public isolated client class TicketingDBClient {
    private final postgresql:Client dbClient;

    public function init(postgresql:Client dbClient) {
        self.dbClient = dbClient;
    }

    // ===== TICKET CREATION & MANAGEMENT =====
    public function createTicket(string passengerId, string tripId, string ticketType, decimal price, string? qrCodeHash) returns string|error {
        string query = `INSERT INTO tickets (passenger_id, trip_id, ticket_type, purchase_price, qr_code_hash, valid_from, valid_until) 
                        VALUES ($1, $2, $3::ticket_type, $4, $5, 
                        (SELECT scheduled_departure FROM trips WHERE id = $2),
                        (SELECT scheduled_arrival + INTERVAL '2 hours' FROM trips WHERE id = $2))
                        RETURNING id`;
        
        var result = self.dbClient->query(query, passengerId, tripId, ticketType, price, qrCodeHash);
        
        record {|string id;|}[] rows = check result.toArray();
        if rows.length() == 0 {
            return error("Failed to create ticket");
        }
        return rows[0].id;
    }

    public function getTicket(string ticketId) returns map<anydata>|error {
        string query = `SELECT 
            t.*,
            u.first_name || ' ' || u.last_name as passenger_name,
            tr.scheduled_departure,
            tr.scheduled_arrival,
            r.origin,
            r.destination,
            v.vehicle_number
            FROM tickets t
            JOIN users u ON t.passenger_id = u.id
            JOIN trips tr ON t.trip_id = tr.id
            JOIN routes r ON tr.route_id = r.id
            JOIN vehicles v ON tr.vehicle_id = v.id
            WHERE t.id = $1`;
        
        var result = self.dbClient->query(query, ticketId);
        record {|string id; string passenger_id; string trip_id; string ticket_type; string status; decimal purchase_price; string valid_from; string valid_until; string qr_code_hash; string boarding_time; string seat_number; string created_at; string updated_at; string passenger_name; string scheduled_departure; string scheduled_arrival; string origin; string destination; string vehicle_number;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Ticket not found");
        }
        return rows[0];
    }

    public function getTicketByQRCode(string qrCodeHash) returns map<anydata>|error {
        string query = `SELECT 
            t.*,
            u.first_name || ' ' || u.last_name as passenger_name,
            tr.id as trip_id,
            tr.status as trip_status
            FROM tickets t
            JOIN users u ON t.passenger_id = u.id
            JOIN trips tr ON t.trip_id = tr.id
            WHERE t.qr_code_hash = $1`;
        
        var result = self.dbClient->query(query, qrCodeHash);
        record {|string id; string passenger_id; string trip_id; string ticket_type; string status; decimal purchase_price; string valid_from; string valid_until; string qr_code_hash; string boarding_time; string seat_number; string created_at; string updated_at; string passenger_name; string trip_status;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Ticket not found");
        }
        return rows[0];
    }

    public function getPassengerTickets(string passengerId, int limit = 50, int offset = 0) returns map<anydata>[]|error {
        string query = `SELECT 
            t.id, t.trip_id, t.ticket_type, t.status, t.purchase_price, 
            t.valid_from, t.valid_until, t.created_at,
            tr.scheduled_departure, r.origin, r.destination, v.vehicle_number
            FROM tickets t
            JOIN trips tr ON t.trip_id = tr.id
            JOIN routes r ON tr.route_id = r.id
            JOIN vehicles v ON tr.vehicle_id = v.id
            WHERE t.passenger_id = $1
            ORDER BY t.created_at DESC
            LIMIT $2 OFFSET $3`;
        
        return self.dbClient->query(query, passengerId, limit, offset);
    }

    // ===== TICKET VALIDATION =====
    public function validateTicket(string ticketId, string tripId) returns boolean|error {
        string query = `UPDATE tickets 
                        SET status = 'validated', boarding_time = CURRENT_TIMESTAMP
                        WHERE id = $1 AND trip_id = $2 
                        AND status = 'paid'
                        AND valid_until > CURRENT_TIMESTAMP
                        AND EXISTS (SELECT 1 FROM trips WHERE id = $2 AND status IN ('boarding', 'scheduled'))
                        RETURNING id`;
        
        var result = self.dbClient->query(query, ticketId, tripId);
        record {|string id;|}[] rows = check result.toArray();
        
        return rows.length() > 0;
    }

    // ===== TICKET STATUS UPDATES =====
    public function updateTicketStatus(string ticketId, string status) returns error? {
        string query = `UPDATE tickets SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`;
        _ = check self.dbClient->execute(query, status, ticketId);
    }

    public function updateTicketSeat(string ticketId, string seatNumber) returns error? {
        string query = `UPDATE tickets SET seat_number = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`;
        _ = check self.dbClient->execute(query, seatNumber, ticketId);
    }

    public function cancelTicket(string ticketId) returns error? {
        string query = `UPDATE tickets SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP WHERE id = $1`;
        _ = check self.dbClient->execute(query, ticketId);
    }

    // ===== TICKET SEARCH & FILTERS =====
    public function searchTickets(TicketSearchRequest search) returns map<anydata>[]|error {
        string baseQuery = `SELECT 
            t.id, t.passenger_id, t.trip_id, t.ticket_type, t.status, t.purchase_price,
            t.created_at, t.valid_until,
            u.first_name || ' ' || u.last_name as passenger_name,
            r.origin, r.destination,
            tr.scheduled_departure
            FROM tickets t
            JOIN users u ON t.passenger_id = u.id
            JOIN trips tr ON t.trip_id = tr.id
            JOIN routes r ON tr.route_id = r.id
            WHERE 1=1`;
        
        string[] params = [];
        int paramCount = 0;

        if search.passengerId is string {
            paramCount += 1;
            baseQuery += ` AND t.passenger_id = $${paramCount.toString()}`;
            params.push(search.passengerId);
        }

        if search.tripId is string {
            paramCount += 1;
            baseQuery += ` AND t.trip_id = $${paramCount.toString()}`;
            params.push(search.tripId);
        }

        if search.status is string {
            paramCount += 1;
            baseQuery += ` AND t.status = $${paramCount.toString()}`;
            params.push(search.status);
        }

        if search.dateFrom is string {
            paramCount += 1;
            baseQuery += ` AND DATE(t.created_at) >= $${paramCount.toString()}`;
            params.push(search.dateFrom);
        }

        if search.dateTo is string {
            paramCount += 1;
            baseQuery += ` AND DATE(t.created_at) <= $${paramCount.toString()}`;
            params.push(search.dateTo);
        }

        baseQuery += " ORDER BY t.created_at DESC";

        return self.dbClient->query(baseQuery, ...params);
    }

    // ===== TICKET STATISTICS =====
    public function getTicketStats() returns map<anydata>|error {
        string query = `SELECT 
            COUNT(*) as total_tickets,
            COUNT(*) FILTER (WHERE status IN ('paid', 'validated')) as active_tickets,
            COUNT(*) FILTER (WHERE status = 'validated') as validated_tickets,
            COUNT(*) FILTER (WHERE status = 'expired') as expired_tickets,
            COALESCE(SUM(purchase_price) FILTER (WHERE status IN ('paid', 'validated')), 0) as total_revenue
            FROM tickets`;
        
        var result = self.dbClient->query(query);
        record {|int total_tickets; int active_tickets; int validated_tickets; int expired_tickets; decimal total_revenue;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Failed to get ticket stats");
        }
        return rows[0];
    }

    public function getTripTicketStats(string tripId) returns map<anydata>|error {
        string query = `SELECT 
            COUNT(*) as total_tickets,
            COUNT(*) FILTER (WHERE status = 'validated') as validated_tickets,
            COUNT(*) FILTER (WHERE status = 'paid') as paid_tickets
            FROM tickets 
            WHERE trip_id = $1`;
        
        var result = self.dbClient->query(query, tripId);
        record {|int total_tickets; int validated_tickets; int paid_tickets;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Failed to get trip ticket stats");
        }
        return rows[0];
    }
}