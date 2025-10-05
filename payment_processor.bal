import ballerinax/kafka;
import ballerina/log;
import ballerina/random;
import ballerina/lang.'value;

configurable string kafkaBootstrapServers = "localhost:9092";
configurable string paymentTopic = "payment-events";
configurable string ticketingTopic = "ticket-events";

configurable float paymentSuccessRate = 0.95;
configurable int maxRetryAttempts = 3;

public isolated client class PaymentProcessor {
    private final kafka:Producer kafkaProducer;
    private final PaymentDBClient paymentDB;

    public function init(PaymentDBClient paymentDB) returns error? {
        self.kafkaProducer = check new (kafkaBootstrapServers);
        self.paymentDB = paymentDB;
        log:printInfo("Payment processor initialized");
    }

    // ===== PAYMENT PROCESSING =====
    public function processPayment(PaymentRequest payment) returns PaymentResponse|error {
        log:printInfo("Processing payment for ticket: " + payment.ticketId);
        
        // Create payment record
        string paymentId = check self.paymentDB->createPayment(payment);
        
        // Simulate payment processing
        boolean isSuccess = self.simulatePaymentProcessing();
        string status = isSuccess ? "completed" : "failed";
        string? transactionId = isSuccess ? "txn_" + self.generateTransactionId() : ();
        string? failureReason = isSuccess ? () : "Payment gateway declined";
        
        // Update payment status
        check self.paymentDB->updatePaymentStatus(paymentId, status, transactionId, failureReason);
        
        // Update ticket status based on payment result
        string ticketStatus = isSuccess ? "paid" : "created";
        check self.paymentDB->updateTicketStatus(payment.ticketId, ticketStatus);
        
        // Send Kafka event
        check self.sendPaymentEvent({
            eventType: "PAYMENT_PROCESSED",
            paymentId: paymentId,
            ticketId: payment.ticketId,
            passengerId: payment.passengerId,
            amount: payment.amount,
            status: status,
            transactionId: transactionId ?: "",
            timestamp: self.getCurrentTimestamp()
        });
        
        return {
            paymentId: paymentId,
            ticketId: payment.ticketId,
            passengerId: payment.passengerId,
            amount: payment.amount,
            currency: payment.currency,
            paymentMethod: payment.paymentMethod,
            status: status,
            transactionId: transactionId ?: "",
            createdAt: self.getCurrentTimestamp()
        };
    }

    // ===== REFUND PROCESSING =====
    public function processRefund(RefundRequest refund) returns RefundResponse|error {
        log:printInfo("Processing refund for payment: " + refund.paymentId);
        
        // Get original payment
        var payment = self.paymentDB->getPayment(refund.paymentId);
        if payment is error {
            return error("Payment not found");
        }
        
        decimal refundAmount = refund.refundAmount ?: <decimal>payment.amount;
        
        // Create refund record
        string refundId = check self.paymentDB->createRefund(refund.paymentId, refund.reason, refundAmount);
        
        // Simulate refund processing (always successful for demo)
        check self.paymentDB->updatePaymentStatus(refundId, "completed", "refund_" + refund.paymentId, ());
        
        // Send refund event
        check self.sendRefundEvent({
            eventType: "REFUND_PROCESSED",
            refundId: refundId,
            paymentId: refund.paymentId,
            amount: refundAmount,
            status: "completed",
            reason: refund.reason,
            timestamp: self.getCurrentTimestamp()
        });
        
        return {
            refundId: refundId,
            paymentId: refund.paymentId,
            refundAmount: refundAmount,
            status: "completed",
            reason: refund.reason,
            createdAt: self.getCurrentTimestamp()
        };
    }

    // ===== PAYMENT STATUS CHECK =====
    public function getPaymentStatus(string paymentId) returns PaymentStatusResponse|error {
        var payment = self.paymentDB->getPayment(paymentId);
        if payment is error {
            return error("Payment not found");
        }
        
        return {
            paymentId: paymentId,
            status: payment.status.toString(),
            failureReason: payment.failure_reason?.toString(),
            processedAt: payment.processed_at?.toString(),
            settledAt: payment.settled_at?.toString()
        };
    }

    // ===== PRIVATE METHODS =====
    private function simulatePaymentProcessing() returns boolean {
        // Simulate payment processing with configurable success rate
        float randomValue = random:createDecimal() / 100.0;
        return randomValue <= paymentSuccessRate;
    }

    private function generateTransactionId() returns string {
        return random:createInclusiveInt(100000, 999999).toString() + 
               random:createInclusiveInt(100000, 999999).toString();
    }

    private function getCurrentTimestamp() returns string {
        return string `${{time:utcNow().format("yyyy-MM-dd'T'HH:mm:ss'Z'")}}`;
    }

    private function sendPaymentEvent(PaymentEvent event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        check self.kafkaProducer->send({
            topic: paymentTopic,
            value: eventJson.toBytes()
        });
        log:printInfo("Sent payment event: " + event.eventType);
    }

    private function sendRefundEvent(RefundEvent event) returns error? {
        string eventJson = check value:toJson(event).toJsonString();
        check self.kafkaProducer->send({
            topic: paymentTopic,
            value: eventJson.toBytes()
        });
        log:printInfo("Sent refund event: " + event.eventType);
    }

    public function close() returns error? {
        return self.kafkaProducer->close();
    }
}