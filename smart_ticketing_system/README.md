# Smart Public Transport Ticketing System

Skeleton package generated with Ballerina for Assignment 2 (DSA612S). The solution targets a microservice architecture with Kafka-backed events, persistent storage, and containerised deployment.

## Services
- Passenger Service (`modules/passenger_service`): registration, authentication, passenger ticket view.
- Transport Service (`modules/transport_service`): route and trip management, publishing schedule updates.
- Ticketing Service (`modules/ticketing_service`): ticket lifecycle orchestration, validation workflow.
- Payment Service (`modules/payment_service`): simulate transactions, publish payment confirmations.
- Notification Service (`modules/notification_service`): distribute alerts to clients based on events.
- Admin Service (`modules/admin_service`): monitoring, reporting, and administrative actions.
- Gateway (`service.bal`): shared entry point that exposes `/system/health` for readiness checks.
- Common Module (`modules/common`): shared types and constants such as Kafka topics.

## Getting Started
1. Install Ballerina 2201.12.7 or later.
2. From this directory run `bal run` to start all HTTP services.
3. Verify the gateway is up: `curl http://localhost:8080/system/health`.

Kafka brokers, MongoDB/SQL, and Docker assets are intentionally omitted at this stage and must be added as the implementation matures.

## Work Breakdown Structure
The following work packages are organised by priority. Owners are responsible for driving their package and coordinating cross-cutting tasks.

### Iteration 1: Foundations
- Patemasella Gawanas
  - Stand up Kafka locally and define topics; document event schemas.
  - Create Docker Compose baseline with Kafka, ZooKeeper, MongoDB/SQL.
- Tinomudaishe Ndhlovu
  - Design database schemas for passengers, trips, tickets, and payments.
  - Implement persistence layer utilities in `modules/common`.
- Charmaine Musheko
  - Build Passenger Service REST endpoints and integrate authentication decisions.
  - Align API docs and specification for onboarding clients.
- Kavangere Ngozu
  - Implement Transport Service REST endpoints plus schedule publication via Kafka.
  - Produce seed data scripts for routes and trips.
- Treasure Kamwi
  - Develop Ticketing Service workflow and Kafka consumers/producers.
  - Coordinate ticket state machine and error handling strategy.
- Reinholdt T Ndjendja
  - Integrate Payment Service with ticketing via Kafka.
  - Implement Notification Service delivery channels and subscription model.

### Iteration 2: Hardening & Ops
- Joint stretch goals: container health checks, Prometheus/Grafana integration, Kubernetes manifests, fault-injection tests, CI workflows.

## Deliverables Checklist
- ✅ Ballerina package skeleton with dedicated modules per microservice.
- ☐ Kafka integration and message contracts.
- ☐ Persistence integration with chosen database.
- ☐ Deployment assets (Docker Compose/K8s) and documentation.
- ☐ Automated tests covering services and event flows.
- ☐ Final presentation deck and demo script.

