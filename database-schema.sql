// Database: transport_ticketing_system

// 1. Users Collection (All user types)
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["email", "password", "userType", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        email: { bsonType: "string" },
        password: { bsonType: "string" },
        userType: { 
          bsonType: "string",
          enum: ["admin", "bus_driver", "train_driver", "passenger"]
        },
        firstName: { bsonType: "string" },
        lastName: { bsonType: "string" },
        phone: { bsonType: "string" },
        isActive: { bsonType: "bool" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" },
        
        // Passenger specific fields
        loyaltyPoints: { bsonType: "int" },
        preferredPayment: { bsonType: "string" },
        
        // Driver specific fields
        licenseNumber: { bsonType: "string" },
        vehicleAssigned: { bsonType: "string" },
        
        // Admin specific fields
        adminLevel: { bsonType: "string" },
        permissions: { 
          bsonType: "array",
          items: { bsonType: "string" }
        }
      }
    }
  }
});

// 2. Routes Collection
db.createCollection("routes", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["routeName", "startLocation", "endLocation", "transportType", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        routeName: { bsonType: "string" },
        routeCode: { bsonType: "string" },
        startLocation: { bsonType: "string" },
        endLocation: { bsonType: "string" },
        transportType: { 
          bsonType: "string",
          enum: ["bus", "train"]
        },
        distance: { bsonType: "double" },
        estimatedDuration: { bsonType: "int" }, // in minutes
        stops: {
          bsonType: "array",
          items: {
            bsonType: "object",
            properties: {
              stopName: { bsonType: "string" },
              stopOrder: { bsonType: "int" },
              estimatedTime: { bsonType: "int" }
            }
          }
        },
        isActive: { bsonType: "bool" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// 3. Trips Collection
db.createCollection("trips", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["routeId", "driverId", "scheduledStart", "scheduledEnd", "status", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        routeId: { bsonType: "objectId" },
        driverId: { bsonType: "objectId" },
        vehicleNumber: { bsonType: "string" },
        scheduledStart: { bsonType: "date" },
        scheduledEnd: { bsonType: "date" },
        actualStart: { bsonType: "date" },
        actualEnd: { bsonType: "date" },
        status: {
          bsonType: "string",
          enum: ["scheduled", "in_progress", "completed", "cancelled", "delayed"]
        },
        currentLocation: { bsonType: "string" },
        delayMinutes: { bsonType: "int" },
        availableSeats: { bsonType: "int" },
        price: { bsonType: "double" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// 4. Tickets Collection
db.createCollection("tickets", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["passengerId", "tripId", "ticketType", "price", "status", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        passengerId: { bsonType: "objectId" },
        tripId: { bsonType: "objectId" },
        ticketType: {
          bsonType: "string",
          enum: ["single", "multiple", "daily", "weekly", "monthly"]
        },
        price: { bsonType: "double" },
        status: {
          bsonType: "string",
          enum: ["CREATED", "PAID", "VALIDATED", "EXPIRED", "CANCELLED"]
        },
        purchaseDate: { bsonType: "date" },
        validationDate: { bsonType: "date" },
        expiryDate: { bsonType: "date" },
        qrCode: { bsonType: "string" },
        validationCount: { bsonType: "int" },
        maxValidations: { bsonType: "int" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// 5. Payments Collection
db.createCollection("payments", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["passengerId", "amount", "currency", "status", "paymentMethod", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        passengerId: { bsonType: "objectId" },
        ticketId: { bsonType: "objectId" },
        amount: { bsonType: "double" },
        currency: { bsonType: "string" },
        status: {
          bsonType: "string",
          enum: ["pending", "completed", "failed", "refunded"]
        },
        paymentMethod: {
          bsonType: "string",
          enum: ["credit_card", "debit_card", "mobile_money", "cash"]
        },
        transactionId: { bsonType: "string" },
        paymentDate: { bsonType: "date" },
        refundAmount: { bsonType: "double" },
        refundDate: { bsonType: "date" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      }
    }
  }
});

// 6. Notifications Collection
db.createCollection("notifications", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["userId", "type", "title", "message", "status", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        userId: { bsonType: "objectId" },
        type: {
          bsonType: "string",
          enum: ["trip_update", "ticket_validation", "payment", "system"]
        },
        title: { bsonType: "string" },
        message: { bsonType: "string" },
        status: {
          bsonType: "string",
          enum: ["sent", "delivered", "read"]
        },
        relatedTripId: { bsonType: "objectId" },
        relatedTicketId: { bsonType: "objectId" },
        sentAt: { bsonType: "date" },
        readAt: { bsonType: "date" },
        createdAt: { bsonType: "date" }
      }
    }
  }
});

// 7. Reports Collection
db.createCollection("reports", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["reportType", "period", "data", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        reportType: {
          bsonType: "string",
          enum: ["ticket_sales", "passenger_traffic", "revenue", "route_usage"]
        },
        period: { bsonType: "string" },
        startDate: { bsonType: "date" },
        endDate: { bsonType: "date" },
        data: { bsonType: "object" },
        generatedBy: { bsonType: "objectId" },
        createdAt: { bsonType: "date" }
      }
    }
  }
});