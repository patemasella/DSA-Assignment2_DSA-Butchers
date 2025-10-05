import ballerina/http;

// User Management Types
public type CreateUserRequest record {|
    string email;
    string password;
    string firstName;
    string lastName;
    string role;
    string? phoneNumber;
|};

public type UpdateUserRequest record {|
    string? email;
    string? firstName;
    string? lastName;
    string? phoneNumber;
    boolean? isActive;
|};

public type UserResponse record {|
    string id;
    string email;
    string firstName;
    string lastName;
    string role;
    string? phoneNumber;
    boolean isActive;
    string createdAt;
    string updatedAt;
|};

// Route Management Types
public type CreateRouteRequest record {|
    string routeCode;
    string origin;
    string destination;
    decimal distanceKm;
    int estimatedDurationMinutes;
|};

public type RouteResponse record {|
    string id;
    string routeCode;
    string origin;
    string destination;
    decimal distanceKm;
    int estimatedDurationMinutes;
    boolean isActive;
    string createdAt;
|};

// Trip Management Types
public type CreateTripRequest record {|
    string routeId;
    string vehicleId;
    string driverId;
    string scheduledDeparture;
    string scheduledArrival;
    decimal basePrice;
|};

public type TripResponse record {|
    string id;
    string routeId;
    string vehicleId;
    string driverId;
    string scheduledDeparture;
    string scheduledArrival;
    string? actualDeparture;
    string? actualArrival;
    string? currentLocation;
    string status;
    int availableSeats;
    decimal basePrice;
    string createdAt;
    string updatedAt;
|};

public type TripUpdateRequest record {|
    string tripId;
    string updateType;
    string message;
    int delayMinutes = 0;
    string? newDepartureTime;
    string? newArrivalTime;
|};

// Reporting Types
public type SalesReportRequest record {|
    string startDate;
    string endDate;
    string? ticketType;
|};

public type SalesReportResponse record {|
    string date;
    string ticketType;
    int hourSlot;
    decimal amountSold;
    int ticketsCount;
|}[];

public type SystemStats record {|
    int totalUsers;
    int activeTrips;
    int ticketsSoldToday;
    decimal revenueToday;
    int totalRoutes;
    int activeVehicles;
|};

public type PassengerTraffic record {|
    string travelDate;
    int passengerCount;
    int uniquePassengers;
|}[];