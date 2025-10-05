# Passenger Service Security Notes

- RSA signing material lives under `modules/passenger_service/resources`. Regenerate for new environments with `openssl genrsa -out private.key 2048` followed by `openssl req -new -x509 -key private.key -out public.crt -days 1825 -subj "/CN=smart-ticketing-system"`.
- Runtime configuration for MongoDB URIs, collection names, JWT key paths, and the access-token TTL is exposed via Ballerina `configurable` values. Override these in `Config.toml` or using environment variables when deploying.
- Registration and login workflows hash passwords with SHA-256, validate email/phone inputs, and return descriptive error payloads when validation fails.
- Helper tests covering hashing and validation live in `modules/passenger_service/tests`. Run them with `bal test passenger_service` (the full package still fails until the other stub modules compile).
- MongoDB clients fall back gracefully when the database is unreachable; expect `500` error responses instead of runtime panics when the backing store is offline.
