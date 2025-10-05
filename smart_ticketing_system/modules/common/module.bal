module smart_ticketing_system.common;

public const string TICKET_REQUEST_TOPIC = "ticket.requests";
public const string PAYMENT_PROCESSED_TOPIC = "payments.processed";
public const string SCHEDULE_UPDATES_TOPIC = "schedule.updates";

public type TicketType "SINGLE"|"MULTI"|"PASS";

public type TicketRequest record {
    string passengerId;
    string routeId;
    string tripId;
    TicketType ticketType;
    decimal amount;
};

public type PaymentConfirmation record {
    string paymentId;
    string ticketId;
    string status;
};

public type ScheduleUpdate record {
    string routeId;
    string message;
    string issuedBy;
};
