import ballerinax/postgresql;
import ballerina/log;
import ballerina/random;

public isolated client class PaymentDBClient {
    private final postgresql:Client dbClient;

    public function init(postgresql:Client dbClient) {
        self.dbClient = dbClient;
    }

    // ===== PAYMENT PROCESSING =====
    public function createPayment(PaymentRequest payment) returns string|error {
        string query = `INSERT INTO payments (ticket_id, passenger_id, amount, currency, payment_method, status) 
                        VALUES ($1, $2, $3, $4, $5, 'pending') RETURNING id`;
        
        var result = self.dbClient->query(query, payment.ticketId, payment.passengerId, 
                                         payment.amount, payment.currency, payment.paymentMethod);
        
        record {|string id;|}[] rows = check result.toArray();
        if rows.length() == 0 {
            return error("Failed to create payment");
        }
        return rows[0].id;
    }

    public function updatePaymentStatus(string paymentId, string status, string? transactionId, string? failureReason) returns error? {
        string query = `UPDATE payments 
                        SET status = $1, transaction_id = $2, failure_reason = $3, processed_at = CURRENT_TIMESTAMP
                        WHERE id = $4`;
        
        _ = check self.dbClient->execute(query, status, transactionId, failureReason, paymentId);
    }

    public function getPayment(string paymentId) returns map<anydata>|error {
        string query = `SELECT 
            p.id, p.ticket_id, p.passenger_id, p.amount, p.currency, p.payment_method, 
            p.status, p.transaction_id, p.failure_reason, p.created_at, p.processed_at,
            t.ticket_type, t.purchase_price
            FROM payments p
            JOIN tickets t ON p.ticket_id = t.id
            WHERE p.id = $1`;
        
        var result = self.dbClient->query(query, paymentId);
        record {|string id; string ticket_id; string passenger_id; decimal amount; string currency; string payment_method; string status; string transaction_id; string failure_reason; string created_at; string processed_at; string ticket_type; decimal purchase_price;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Payment not found");
        }
        return rows[0];
    }

    public function getPaymentByTicket(string ticketId) returns map<anydata>|error {
        string query = `SELECT id, status, amount, transaction_id
                        FROM payments 
                        WHERE ticket_id = $1 
                        ORDER BY created_at DESC 
                        LIMIT 1`;
        
        var result = self.dbClient->query(query, ticketId);
        record {|string id; string status; decimal amount; string transaction_id;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Payment not found for ticket");
        }
        return rows[0];
    }

    public function getPassengerPayments(string passengerId, int limit = 50, int offset = 0) returns map<anydata>[]|error {
        string query = `SELECT 
            p.id, p.ticket_id, p.amount, p.currency, p.payment_method, p.status,
            p.transaction_id, p.created_at, p.processed_at,
            t.ticket_type, r.origin, r.destination
            FROM payments p
            JOIN tickets t ON p.ticket_id = t.id
            JOIN trips tr ON t.trip_id = tr.id
            JOIN routes r ON tr.route_id = r.id
            WHERE p.passenger_id = $1
            ORDER BY p.created_at DESC
            LIMIT $2 OFFSET $3`;
        
        return self.dbClient->query(query, passengerId, limit, offset);
    }

    // ===== REFUND PROCESSING =====
    public function createRefund(string paymentId, string reason, decimal refundAmount) returns string|error {
        string query = `INSERT INTO payments (ticket_id, passenger_id, amount, currency, payment_method, status, transaction_id)
                        SELECT ticket_id, passenger_id, $1, currency, 'refund', 'pending', 'refund_' || id
                        FROM payments WHERE id = $2
                        RETURNING id`;
        
        var result = self.dbClient->query(query, -refundAmount, paymentId);
        record {|string id;|}[] rows = check result.toArray();
        
        if rows.length() == 0 {
            return error("Failed to create refund");
        }
        return rows[0].id;
    }

    // ===== PAYMENT STATISTICS =====
    public function getPaymentStats(string? date) returns map<anydata>|error {
        string baseQuery = `SELECT 
            COUNT(*) as total_payments,
            COUNT(*) FILTER (WHERE status = 'completed') as successful_payments,
            COUNT(*) FILTER (WHERE status = 'failed') as failed_payments,
            COALESCE(SUM(amount) FILTER (WHERE status = 'completed'), 0) as total_revenue
            FROM payments 
            WHERE amount > 0`;
        
        if date is string {
            var result = self.dbClient->query(baseQuery + " AND DATE(created_at) = $1", date);
            record {|int total_payments; int successful_payments; int failed_payments; decimal total_revenue;|}[] rows = check result.toArray();
            if rows.length() > 0 {
                return rows[0];
            }
        } else {
            var result = self.dbClient->query(baseQuery);
            record {|int total_payments; int successful_payments; int failed_payments; decimal total_revenue;|}[] rows = check result.toArray();
            if rows.length() > 0 {
                return rows[0];
            }
        }
        
        return error("Failed to get payment stats");
    }

    // ===== TICKET STATUS UPDATE =====
    public function updateTicketStatus(string ticketId, string status) returns error? {
        string query = `UPDATE tickets SET status = $1 WHERE id = $2`;
        _ = check self.dbClient->execute(query, status, ticketId);
    }
}