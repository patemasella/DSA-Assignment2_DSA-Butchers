// Route Types
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

public type UpdateRouteRequest record {|
    string? origin;
    string? destination;
    decimal? distanceKm;
    int? estimatedDurationMinutes;
    boolean? isActive;
|};

// Trip Types
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
    string? currentLocation;
    string? status;
    string? actualDeparture;
    string? actualArrival;
|};

public type TripSearchRequest record {|
    string? routeId;
    string? vehicleId;
    string? driverId;
    string? status;
    string? dateFrom;
    string? dateTo;
|};

public type TripDetailResponse record {|
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
    // Joined data
    string routeCode;
    string origin;
    string destination;
    string vehicleNumber;
    string vehicleType;
    string driverName;
    int totalSeats;
|};

// Vehicle Types
public type CreateVehicleRequest record {|
    string vehicleNumber;
    string vehicleType;
    int capacity;
    string? model;
|};

public type VehicleResponse record {|
    string id;
    string vehicleNumber;
    string vehicleType;
    int capacity;
    string? model;
    boolean isActive;
    string createdAt;
|};

public type UpdateVehicleRequest record {|
    string? vehicleNumber;
    string? vehicleType;
    int? capacity;
    string? model;
    boolean? isActive;
|};

public type VehicleLocationUpdate record {|
    string vehicleId;
    string currentLocation;
    decimal? latitude;
    decimal? longitude;
    string timestamp;
|};

// Schedule Types
public type ScheduleRequest record {|
    string routeId;
    string startDate;
    string endDate;
    string[] times;  // Array of times in HH:MM format
    string vehicleId;
    string driverId;
    decimal basePrice;
|};

public type ScheduleResponse record {|
    string message;
    int tripsCreated;
    string[] tripIds;
|};

// Kafka Event Types
public type TripEvent record {|
    string eventType;
    string tripId;
    string routeId;
    string vehicleId;
    string driverId;
    string status;
    string? currentLocation;
    string timestamp;
|};

public type VehicleEvent record {|
    string eventType;
    string vehicleId;
    string vehicleNumber;
    string? currentLocation;
    string status;
    string timestamp;
|};

// Common Response Types
public type SuccessResponse record {|
    string message;
    string? id;
|};

public type ErrorResponse record {|
    string message;
    string? code;
|};

public type StatsResponse record {|
    int totalRoutes;
    int activeTrips;
    int totalVehicles;
    int availableVehicles;
    int scheduledTripsToday;
|};