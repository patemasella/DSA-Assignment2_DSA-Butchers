// common/sample-data.bal
import ballerina/uuid;

public function generateSamplePassenger() returns Passenger {
    string passengerId = "pass_" + uuid:create();
    return {
        id: passengerId,
        name: "John Doe",
        email: "john.doe@email.com",
        phone: "+264811234567",
        passwordHash: "hashed_password_123", // In real system, use bcrypt
        balance: 100.00,
        registeredAt: time:utcNow(),
        isActive: true,
        preferences: ["email_notifications", "sms_alerts"]
    };
}

public function generateSampleRoute() returns Route {
    return {
        id: "route_001",
        name: "City Center - Katutura Express",
        description: "Direct route from City Center to Katutura",
        fromLocation: "Windhoek City Center",
        toLocation: "Katutura Terminal",
        distance: 8.5,
        basePrice: 15.50,
        estimatedDuration: 25,
        stops: ["City Center", "Wernhill Park", "Katutura Hospital", "Katutura Terminal"],
        isActive: true
    };
}

public function generateSampleTrip() returns Trip {
    time:Utc now = time:utcNow();
    time:Utc departure = time:utcAddSeconds(now, 3600); // 1 hour from now
    
    return {
        id: "trip_" + uuid:create(),
        routeId: "route_001",
        vehicleId: "BUS-042",
        driverId: "driver_123",
        scheduledDeparture: departure,
        scheduledArrival: time:utcAddSeconds(departure, 1500), // 25 minutes later
        availableSeats: 40,
        totalSeats: 45,
        status: SCHEDULED,
        currentPrice: 15.50
    };
}