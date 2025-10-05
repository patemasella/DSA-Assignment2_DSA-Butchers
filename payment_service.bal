import ballerina/http;
import ballerinax/postgresql;
import ballerina/log;
import ballerinax/kafka;
import ballerina/lang.'value;

configurable int paymentServicePort = 8083;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUsername = "transport_user";
configurable string dbPassword = "transport_password";
configurable string dbName = "transport_system";

configurable string kafkaBootstrapServers = "localhost:9092";
configurable float paymentSuccessRate = 0.95;

listener http:Listener paymentListener = new(paymentServicePort);

// Simple authentication validation
public isolated function validateAuth(string authHeader) returns string|error {
    if !authHeader.startsWith("Bearer ") {
        return error("Invalid authentication");
    }
    return authHeader.replace("Bearer ", "");
}

service /payment on paymentListener {
    private final PaymentDBClient paymentDB;
    private final PaymentProcessor paymentProcessor;
    private final kafka:Producer kafkaProducer;

    function init() returns error? {
        postgresql:Client dbClient = check new (
            host = dbHost,
            user = dbUsername,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        self.paymentDB = new (dbClient);
        self.paymentProcessor = check new (self.paymentDB);
        self.kafkaProducer = check new (kafkaBootstrapServers);
        
        log:printInfo("Payment Service with Kafka started on port " + paymentServicePort.toString());
    }

    // ===== HEALTH CHECK =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/health"
    }
    resource function get health() returns string {
        return "Payment Service is healthy!";
    }

    // ===== PAYMENT PROCESSING WITH KAFKA =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/payments"
    }
    resource function post payments(@http:Header {name: "Authorization"} string authHeader,
                                   PaymentRequest request) returns PaymentResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        string|error passengerId = validateAuth(authHeader);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }

        // Validate that the passenger ID matches
        if passengerId != request.passengerId {
            return http:UNAUTHORIZED;
        }

        log:printInfo("Processing payment for passenger: " + request.passengerId);
        
        // Create payment record
        string paymentId = check self.paymentDB.createPayment(request);
        
        // Simulate payment processing
        boolean isSuccess = self.simulatePaymentProcessing();
        string status = isSuccess ? "completed" : "failed";
        string? transactionId = isSuccess ? "txn_" + self.generateTransactionId() : ();
        string? failureReason = isSuccess ? () : "Payment gateway declined";
        
        // Update payment status
        check self.paymentDB.updatePaymentStatus(paymentId, status, transactionId, failureReason);
        
        // Update ticket status based on payment result
        string ticketStatus = isSuccess ? "paid" : "created";
        check self.paymentDB.updateTicketStatus(request.ticketId, ticketStatus);

        // Send Kafka event for payment processing
        _ = self.sendKafkaEvent("payment-events", {
            "eventType": "PAYMENT_PROCESSED",
            "paymentId": paymentId,
            "ticketId": request.ticketId,
            "passengerId": request.passengerId,
            "amount": request.amount,
            "currency": request.currency,
            "paymentMethod": request.paymentMethod,
            "status": status,
            "transactionId": transactionId ?: "",
            "failureReason": failureReason,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "payment-service"
        });

        // Also send to ticket-events for ticketing service
        if isSuccess {
            _ = self.sendKafkaEvent("ticket-events", {
                "eventType": "TICKET_PAID",
                "ticketId": request.ticketId,
                "paymentId": paymentId,
                "passengerId": request.passengerId,
                "amount": request.amount,
                "timestamp": self.getCurrentTimestamp(),
                "sourceService": "payment-service"
            });

            // Send success notification
            _ = self.sendKafkaEvent("notifications", {
                "eventType": "PAYMENT_SUCCESS",
                "userId": request.passengerId,
                "title": "Payment Successful",
                "message": "Your payment of " + request.amount.toString() + " " + request.currency + " was processed successfully",
                "notificationType": "payment_success",
                "paymentId": paymentId,
                "timestamp": self.getCurrentTimestamp(),
                "sourceService": "payment-service"
            });
        } else {
            // Send failure notification
            _ = self.sendKafkaEvent("notifications", {
                "eventType": "PAYMENT_FAILED",
                "userId": request.passengerId,
                "title": "Payment Failed",
                "message": "Your payment could not be processed. Please try again.",
                "notificationType": "payment_failure",
                "paymentId": paymentId,
                "timestamp": self.getCurrentTimestamp(),
                "sourceService": "payment-service"
            });
        }
        
        return {
            paymentId: paymentId,
            ticketId: request.ticketId,
            passengerId: request.passengerId,
            amount: request.amount,
            currency: request.currency,
            paymentMethod: request.paymentMethod,
            status: status,
            transactionId: transactionId ?: "",
            createdAt: self.getCurrentTimestamp()
        };
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/payments/{paymentId}"
    }
    resource function get payments/[string paymentId](@http:Header {name: "Authorization"} string authHeader) 
            returns PaymentStatusResponse|http:Unauthorized|http:NotFound|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var paymentStatus = self.paymentProcessor->getPaymentStatus(paymentId);
        if paymentStatus is error {
            return http:NOT_FOUND;
        }
        
        return paymentStatus;
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/payments"
    }
    resource function get payments(@http:Header {name: "Authorization"} string authHeader,
                                  int? limit, int? offset) returns PaymentResponse[]|http:Unauthorized|http:InternalServerError {
        string|error passengerId = validateAuth(authHeader);
        if passengerId is error {
            return http:UNAUTHORIZED;
        }
        
        int actualLimit = limit ?: 50;
        int actualOffset = offset ?: 0;
        
        var payments = self.paymentDB->getPassengerPayments(passengerId, actualLimit, actualOffset);
        if payments is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return from var payment in payments
            select {
                paymentId: payment.id.toString(),
                ticketId: payment.ticket_id.toString(),
                passengerId: passengerId,
                amount: <decimal>payment.amount,
                currency: payment.currency.toString(),
                paymentMethod: payment.payment_method.toString(),
                status: payment.status.toString(),
                transactionId: payment.transaction_id?.toString() ?: "",
                createdAt: payment.created_at.toString()
            };
    }

    // ===== REFUND PROCESSING WITH KAFKA =====
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/refunds"
    }
    resource function post refunds(@http:Header {name: "Authorization"} string authHeader,
                                  RefundRequest request) returns RefundResponse|http:Unauthorized|http:BadRequest|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        // Simple admin check for refunds
        if !authHeader.startsWith("Bearer admin-") {
            return http:UNAUTHORIZED;
        }
        
        log:printInfo("Processing refund for payment: " + request.paymentId);
        
        // Get original payment
        var payment = self.paymentDB.getPayment(request.paymentId);
        if payment is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        decimal refundAmount = request.refundAmount ?: <decimal>payment.amount;
        
        // Create refund record
        string refundId = check self.paymentDB.createRefund(request.paymentId, request.reason, refundAmount);
        
        // Update refund status
        check self.paymentDB.updatePaymentStatus(refundId, "completed", "refund_" + request.paymentId, ());

        // Send refund event
        _ = self.sendKafkaEvent("payment-events", {
            "eventType": "REFUND_PROCESSED",
            "refundId": refundId,
            "paymentId": request.paymentId,
            "amount": refundAmount,
            "status": "completed",
            "reason": request.reason,
            "timestamp": self.getCurrentTimestamp(),
            "sourceService": "payment-service"
        });

        return {
            refundId: refundId,
            paymentId: request.paymentId,
            refundAmount: refundAmount,
            status: "completed",
            reason: request.reason,
            createdAt: self.getCurrentTimestamp()
        };
    }

    // ===== PAYMENT METHODS =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/payment-methods"
    }
    resource function get payment-methods() returns PaymentMethodInfo[] {
        return [
            {
                method: "credit_card",
                description: "Credit Card",
                enabled: true
            },
            {
                method: "debit_card", 
                description: "Debit Card",
                enabled: true
            },
            {
                method: "mobile_money",
                description: "Mobile Money",
                enabled: true
            },
            {
                method: "bank_transfer",
                description: "Bank Transfer", 
                enabled: false
            }
        ];
    }

    // ===== PAYMENT STATISTICS (Admin) =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/stats"
    }
    resource function get stats(@http:Header {name: "Authorization"} string authHeader,
                               string? date) returns map<anydata>|http:Unauthorized|http:InternalServerError {
        if !authHeader.startsWith("Bearer admin-") {
            return http:UNAUTHORIZED;
        }
        
        var stats = self.paymentDB->getPaymentStats(date);
        if stats is error {
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return stats;
    }

    // ===== TICKET PAYMENT STATUS =====
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/tickets/{ticketId}/payment"
    }
    resource function get tickets/[string ticketId]/payment(@http:Header {name: "Authorization"} string authHeader) 
            returns map<anydata>|http:Unauthorized|http:NotFound|http:InternalServerError {
        string|error userId = validateAuth(authHeader);
        if userId is error {
            return http:UNAUTHORIZED;
        }
        
        var payment = self.paymentDB->getPaymentByTicket(ticketId);
        if payment is error {
            return http:NOT_FOUND;
        }
        
        return {
            paymentId: payment.id.toString(),
            status: payment.status.toString(),
            amount: <decimal>payment.amount,
            transactionId: payment.transaction_id?.toString()
        };
    }

    // ===== HELPER METHODS =====
    private function simulatePaymentProcessing() returns boolean {
        // Simulate payment processing with configurable success rate
        float randomValue = <float>float:floor((<float>random:createInclusiveInt(0, 100)) / 100.0);
        return randomValue <= paymentSuccessRate;
    }

    private function generateTransactionId() returns string {
        return random:createInclusiveInt(100000, 999999).toString() + 
               random:createInclusiveInt(100000, 999999).toString();
    }

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