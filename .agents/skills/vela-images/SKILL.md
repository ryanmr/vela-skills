---
name: vela-images
description: "Docker image selection for Vela steps; alpine variants, version pinning, pull policies, and recommended images for Go, Node, Python, Java, Rust, Ruby, and .NET."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Choose the right Docker images for your Vela pipeline steps. Prefer alpine variants, pin to major or major.minor versions, and use `pull: always` for mutable tags. Every step runs inside a Docker container, and image choice directly affects build speed, reliability, and security.

## General Recommendations

### Prefer Alpine Variants

Alpine-based images are significantly smaller and faster to pull. Most official Docker images offer `-alpine` variants:

```yaml
# Prefer this
image: golang:1.23-alpine

# Over this
image: golang:1.23
```

Size comparison examples:
- `node:22` ~1GB vs `node:22-alpine` ~130MB
- `golang:1.23` ~800MB vs `golang:1.23-alpine` ~250MB
- `python:3.13` ~900MB vs `python:3.13-alpine` ~50MB

Smaller images mean faster `docker pull` times, which directly reduces build duration -- especially on workers without cached images.

### Pin to Major or Minor Versions

Don't pin too specifically (avoid patch-level pins), but don't use `latest` for production builds either. Pin to the **major** or **major.minor** level:

```yaml
# Good -- pins to major, gets security patches automatically
image: node:22-alpine
image: golang:1.23-alpine
image: python:3.13-alpine

# Avoid -- too specific, misses security patches
image: node:22.11.2-alpine
image: golang:1.23.5-alpine

# Avoid for production -- unpredictable, may break without warning
image: node:latest
image: golang:latest
```

The sweet spot is major version (e.g., `node:22-alpine`) or major.minor (e.g., `golang:1.23-alpine`). This balances reproducibility with receiving security updates.

### Use `pull: always` for Mutable Tags

If you use tags that can change (anything other than a SHA digest), consider `pull: always` to avoid stale cached images:

```yaml
steps:
  - name: build
    image: golang:1.23-alpine
    pull: always
    commands:
      - go build .
```

This is especially important for tags like `latest`, `stable`, or any tag without a patch version. For internal/private images that update frequently, `pull: always` prevents "works on one worker, fails on another" issues.

## Recommended Base Images by Language

### Go

```yaml
image: golang:1.23-alpine
```

Note: If your Go project uses CGO, you may need the non-alpine variant (or install build dependencies), because alpine uses musl libc instead of glibc:

```yaml
# For CGO-dependent builds
image: golang:1.23
environment:
  CGO_ENABLED: "1"

# Or install gcc in alpine
image: golang:1.23-alpine
commands:
  - apk add --no-cache gcc musl-dev
  - go build .
```

### Node.js / JavaScript

```yaml
image: node:22-alpine
```

### Python

```yaml
image: python:3.13-alpine
```

Note: Some Python packages with C extensions need build tools:

```yaml
image: python:3.13-alpine
commands:
  - apk add --no-cache gcc musl-dev libffi-dev
  - pip install -r requirements.txt
```

### Java / JVM

```yaml
# Maven
image: maven:3-eclipse-temurin-21-alpine

# Gradle
image: gradle:8-jdk21-alpine
```

### Rust

```yaml
image: rust:1-alpine
commands:
  - apk add --no-cache musl-dev
  - cargo build --release
```

### Ruby

```yaml
image: ruby:3-alpine
```

### .NET

```yaml
image: mcr.microsoft.com/dotnet/sdk:9.0-alpine
```

### General Purpose / Shell Scripts

```yaml
image: alpine:3
```

Alpine is the go-to for lightweight shell-based steps. It includes `sh`, `wget`, and basic utilities. Add more with `apk add --no-cache <package>`.

## Service Images

For service containers (databases, caches), also prefer alpine variants. See the vela-services skill for full service container configuration:

```yaml
services:
  - name: postgres
    image: postgres:16-alpine

  - name: redis
    image: redis:7-alpine

  - name: mysql
    image: mysql:8
    # Note: MySQL doesn't offer an official alpine variant
```

## Vela Plugin Images

Official Vela plugins use the `target/vela-*` prefix. Always use `pull: always` with plugins to get the latest bug fixes. See the vela-plugins skill for plugin configuration and parameters:

```yaml
steps:
  - name: publish
    image: target/vela-kaniko:latest
    pull: always
    parameters:
      registry: index.docker.io
      repo: index.docker.io/myorg/myapp
```

For plugins, `latest` is acceptable because the plugin maintainers ensure backward compatibility.

## Private / Internal Images

For images from private registries, ensure the Vela worker has credentials configured to pull them. See the vela-secrets skill for configuring registry credentials:

```yaml
steps:
  - name: build
    image: registry.company.com/myorg/build-image:2
    pull: always
    commands:
      - make build
```

Pin internal images to a versioned tag that your team controls. This prevents surprise breakages when someone pushes a new version.

## Examples

### Example: Multi-Language Pipeline

```yaml
version: "1"

stages:
  backend:
    steps:
      - name: test go
        image: golang:1.23-alpine
        pull: always
        commands:
          - go test ./...

  frontend:
    steps:
      - name: test node
        image: node:22-alpine
        pull: always
        commands:
          - npm ci
          - npm test

  infra:
    steps:
      - name: validate terraform
        image: hashicorp/terraform:1-alpine
        pull: always
        commands:
          - terraform init
          - terraform validate
```

### Example: Alpine with Extra Tools

```yaml
steps:
  - name: check links
    image: alpine:3
    commands:
      - apk add --no-cache curl jq
      - curl -sf https://api.example.com/health | jq .status
```

## Pitfalls

- The `latest` tag on language images (like `node:latest`) is a moving pointer that can jump to a new major version at any time. When that happens, your build breaks with no code change on your side, and the failure may be cryptic (new deprecation warnings, changed defaults, removed APIs). Pinning to at least the major version (e.g., `node:22-alpine`) gives you a stable base while still receiving minor and patch updates.
- Full (non-alpine) images carry a complete Debian or Ubuntu userspace that most CI workloads never touch. The difference is dramatic -- `python:3.13` is roughly 900MB while `python:3.13-alpine` is about 50MB. On a Vela worker without cached images, that's the difference between a few seconds and over a minute just for the pull step, and it adds up across every step in your pipeline.
- Pinning to an exact patch version (e.g., `node:22.11.2-alpine`) seems safe but creates a maintenance burden: you never receive security patches automatically, and you have to manually bump the tag for every update. The major or major.minor level is the sweet spot -- specific enough to avoid breaking changes, loose enough to pick up fixes.
- Alpine Linux uses `musl libc` instead of `glibc`, which means pre-compiled binaries built against glibc may segfault or produce a confusing "not found" error (the dynamic linker is missing, not the file itself). If you encounter this, either switch to the non-alpine variant of the image or install `gcompat` for a glibc compatibility layer.
- Vela workers cache images locally, so a mutable tag (like `v2` or `stable`) on a private image may resolve to a stale version on some workers but not others. This creates "works on my build, fails on yours" situations that are maddening to debug. Using `pull: always` forces a fresh pull every time, which costs a few seconds but guarantees consistency across workers.
- If you find yourself running `apk add --no-cache gcc musl-dev ...` in three different steps, each one is paying that install cost independently. Building a custom image with those tools pre-installed moves that cost to image build time (once) rather than pipeline run time (every build), and it makes your pipeline YAML cleaner too.

## Quick Reference

| Language  | Recommended Image                          |
|-----------|--------------------------------------------|
| Go        | `golang:1.23-alpine`                       |
| Node.js   | `node:22-alpine`                           |
| Python    | `python:3.13-alpine`                       |
| Java      | `maven:3-eclipse-temurin-21-alpine`        |
| Rust      | `rust:1-alpine`                            |
| Ruby      | `ruby:3-alpine`                            |
| .NET      | `mcr.microsoft.com/dotnet/sdk:9.0-alpine`  |
| Shell     | `alpine:3`                                 |
| Postgres  | `postgres:16-alpine`                       |
| Redis     | `redis:7-alpine`                           |
| Plugins   | `target/vela-*:latest` (with `pull: always`) |

**Tag strategy:** `major-alpine` or `major.minor-alpine` -- not too specific, not too loose.
