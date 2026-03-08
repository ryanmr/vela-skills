---
name: vela-services
description: "Service containers for integration testing in Vela: Postgres, Redis, MySQL, Elasticsearch. Covers the services key, networking by container name, readiness checks, and detached steps."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Add service containers to your Vela pipeline for integration testing against databases, caches, or other dependencies. Services start before steps and remain available for the entire pipeline duration.

Services run in the same network as your step containers, so reach them by their `name` as the hostname.

## Service Keys

| Key           | Required | Type            | Description                                      |
|---------------|----------|-----------------|--------------------------------------------------|
| `name`        | Y        | string          | Unique identifier (also used as hostname)        |
| `image`       | Y        | string          | Docker image to run                              |
| `pull`        | N        | string          | Pull policy: `always`, `never`, `not_present`, `on_start` |
| `environment` | N        | map or []string | Environment variables for the service            |
| `entrypoint`  | N        | []string        | Override container entrypoint                    |
| `ports`       | N        | []string        | Port mappings                                    |
| `ulimits`     | N        | []struct        | User limits                                      |
| `user`        | N        | string          | Run as specific user                             |

## Networking

Services are accessible from step containers **by name**. The service name becomes the DNS hostname:

```yaml
services:
  - name: postgres
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: testuser
      POSTGRES_PASSWORD: testpass

steps:
  - name: run tests
    image: golang:1.23-alpine
    commands:
      # Connect to postgres using the service name as hostname
      - go test ./... -db-host=postgres -db-port=5432
```

No special port mapping is needed -- use the container's default ports.

## Startup Timing

Services start before steps, but there's **no built-in readiness check**. Many services (databases, Elasticsearch, etc.) need time to initialize before they accept connections. You need to handle this yourself with a wait/retry step:

```yaml
services:
  - name: postgres
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: testuser
      POSTGRES_PASSWORD: testpass

steps:
  - name: wait for postgres
    image: postgres:16-alpine
    commands:
      - |
        for i in $(seq 1 30); do
          pg_isready -h postgres -U testuser && exit 0
          sleep 1
        done
        echo "Postgres did not become ready" && exit 1

  - name: run tests
    image: golang:1.23-alpine
    commands:
      - go test ./...
```

## Environment Variables

Services receive the same built-in Vela variables as steps (build info, repo info, etc.) plus `VELA_SERVICE_*` variables:

| Variable                    | Description                   |
|-----------------------------|-------------------------------|
| `VELA_SERVICE_NAME`         | Name of the service           |
| `VELA_SERVICE_NUMBER`       | Service number in pipeline    |
| `VELA_SERVICE_IMAGE`        | Image used                    |
| `VELA_SERVICE_STATUS`       | Service status                |

Configure service-specific environment with the `environment` key:

```yaml
services:
  - name: redis
    image: redis:7-alpine
    environment:
      REDIS_ARGS: "--maxmemory 256mb"
```

## Port Mapping

Explicit port mapping is rarely needed because services share a network with steps and expose their default ports automatically. Only map ports when you need to remap a non-standard port or expose a service outside the build network:

```yaml
services:
  - name: postgres
    image: postgres:16-alpine
    ports:
      - "5432:5432"
```

## Examples

### Example: PostgreSQL Integration Tests

```yaml
version: "1"

services:
  - name: postgres
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: testuser
      POSTGRES_PASSWORD: testpass

steps:
  - name: wait for db
    image: postgres:16-alpine
    commands:
      - |
        for i in $(seq 1 30); do
          pg_isready -h postgres -U testuser && exit 0
          sleep 1
        done
        exit 1

  - name: migrate
    image: myorg/migrate:latest
    environment:
      DATABASE_URL: "postgres://testuser:testpass@postgres:5432/testdb?sslmode=disable"
    commands:
      - migrate up

  - name: test
    image: golang:1.23-alpine
    environment:
      DATABASE_URL: "postgres://testuser:testpass@postgres:5432/testdb?sslmode=disable"
    commands:
      - go test ./...
```

### Example: Redis Cache

```yaml
version: "1"

services:
  - name: redis
    image: redis:7-alpine

steps:
  - name: wait for redis
    image: redis:7-alpine
    commands:
      - |
        for i in $(seq 1 15); do
          redis-cli -h redis ping && exit 0
          sleep 1
        done
        exit 1

  - name: test
    image: node:22-alpine
    environment:
      REDIS_URL: "redis://redis:6379"
    commands:
      - npm ci
      - npm test
```

### Example: Multiple Services

```yaml
version: "1"

services:
  - name: postgres
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: testuser
      POSTGRES_PASSWORD: testpass

  - name: redis
    image: redis:7-alpine

  - name: elasticsearch
    image: elasticsearch:8-alpine
    environment:
      discovery.type: single-node
      ES_JAVA_OPTS: "-Xms512m -Xmx512m"

steps:
  - name: wait for services
    image: alpine:3
    commands:
      - apk add --no-cache postgresql-client redis netcat-openbsd
      - |
        for i in $(seq 1 30); do
          pg_isready -h postgres -U testuser 2>/dev/null && break
          sleep 1
        done
      - |
        for i in $(seq 1 15); do
          redis-cli -h redis ping 2>/dev/null && break
          sleep 1
        done
      - |
        for i in $(seq 1 60); do
          nc -z elasticsearch 9200 && break
          sleep 2
        done

  - name: test
    image: myorg/myapp:test
    commands:
      - ./run-integration-tests.sh
```

### Example: Detached Step as Service Alternative

Use `detach: true` on a step when you need more control over startup timing or configuration than the `services:` block provides:

```yaml
steps:
  - name: mock-api
    image: myorg/mock-server:latest
    detach: true
    environment:
      PORT: "8080"
      MOCK_CONFIG: /vela/src/github.com/myorg/myrepo/mocks/config.json

  - name: wait for mock
    image: alpine:3
    commands:
      - apk add --no-cache curl
      - |
        for i in $(seq 1 15); do
          curl -sf http://mock-api:8080/health && exit 0
          sleep 1
        done
        exit 1

  - name: test
    image: node:22-alpine
    environment:
      API_URL: "http://mock-api:8080"
    commands:
      - npm test
```

## Pitfalls

- Vela starts service containers before step execution begins, but "started" just means the container is running -- the application inside (Postgres, Redis, etc.) may still be initializing. Without a readiness check, your first step can fail with a connection error simply because it ran faster than the service could boot. A simple retry loop (polling with `pg_isready`, `redis-cli ping`, etc.) handles this reliably.
- Service containers are on a shared Docker network and are addressable by their `name` field as a DNS hostname. Using `localhost` won't resolve to the service because each container has its own network namespace -- `localhost` refers to the step container itself, not the service.
- Service containers run for the entire pipeline lifetime, not just during the steps that need them. If you have a heavy service (like Elasticsearch) that only one step uses, it's sitting idle consuming memory and CPU for every other step. For those cases, a step with `detach: true` is lighter-weight because you control exactly when it starts in the step sequence.
- Most official database images require certain environment variables to initialize properly (e.g., Postgres needs `POSTGRES_PASSWORD`). Without them, the container may start, immediately fail its entrypoint script, and exit -- and your readiness check will just time out with no obvious explanation. Check the image's Docker Hub docs for required variables. Prefer alpine variants (e.g., `postgres:16-alpine`) to reduce pull times; see the vela-images skill for image selection guidance.
- Services like Elasticsearch or Kafka can take 30-60 seconds to become ready, significantly longer than a simple key-value store like Redis. If your readiness loop only tries for 10 seconds, you'll get intermittent failures that look like infrastructure problems but are really just impatient timeouts. Be generous -- a longer wait loop costs almost nothing compared to a failed build retry.

## Quick Reference

```yaml
services:
  - name: service-name      # hostname for network access
    image: org/image:tag     # Docker image
    pull: not_present        # always | never | not_present | on_start
    environment:             # service config
      KEY: value
    entrypoint:              # override entrypoint
      - /custom/entrypoint
    ports:                   # port mapping (usually not needed)
      - "8080:5432"

# Access from steps: use service name as hostname
# postgres -> postgres:5432
# redis -> redis:6379
# elasticsearch -> elasticsearch:9200
```
