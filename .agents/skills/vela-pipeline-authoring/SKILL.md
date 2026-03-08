---
name: vela-pipeline-authoring
description: "Writing .vela.yml from scratch: steps vs stages, available keys, metadata (auto_cancel, clone), image pull policies, the workspace model, and global environment variables."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Create a `.vela.yml` file at the root of your repository to define how code is built, tested, and deployed. Pipelines are composed of **steps** (sequential) or **stages** (parallel), each running in ephemeral Docker containers on the Vela worker.

Every pipeline needs at minimum a `version` key and either a `steps` or `stages` block. Vela automatically injects a clone step that checks out your code into the workspace before your steps run.

## Pipeline Structure

A Vela pipeline has these top-level keys:

| Key           | Required | Description                                    |
|---------------|----------|------------------------------------------------|
| `version`     | Y        | Pipeline version, always `"1"`                 |
| `steps`       | Y*       | Sequential step list (*or use `stages`)        |
| `stages`      | Y*       | Parallel stage groups (*or use `steps`)        |
| `secrets`     | N        | Secret declarations                            |
| `services`    | N        | Long-running service containers                |
| `environment` | N        | Global environment variables                   |
| `metadata`    | N        | Compiler directives (clone, auto_cancel, etc.) |
| `templates`   | N        | External template references                   |
| `deployment`  | N        | Deployment target/parameter config             |

You must use **either** `steps` or `stages` -- never both in the same pipeline, because the compiler cannot determine which execution model to use when both are present.

## Steps vs Stages

**Steps** run sequentially, top to bottom. This is the simplest model and should be your default choice:

```yaml
version: "1"

steps:
  - name: test
    image: golang:1.23-alpine
    commands:
      - go test ./...

  - name: build
    image: golang:1.23-alpine
    commands:
      - go build -o app .
```

**Stages** run in parallel by default, with optional dependency ordering via `needs:`. Use stages only when you genuinely need parallel execution:

```yaml
version: "1"

stages:
  test:
    steps:
      - name: run tests
        image: golang:1.23-alpine
        commands:
          - go test ./...

  lint:
    steps:
      - name: run linter
        image: golangci/golangci-lint:v1-alpine
        commands:
          - golangci-lint run
```

**Recommendation:** Start with `steps`. Only move to `stages` when sequential execution is a bottleneck. Stages add complexity around dependency ordering and compile-time pruning. See the vela-stages skill for details on stage mechanics.

## Step Keys

Every step requires `name` and `image`. The most commonly used keys:

| Key           | Required | Description                                              |
|---------------|----------|----------------------------------------------------------|
| `name`        | Y        | Unique identifier for the step                           |
| `image`       | Y        | Docker image to run                                      |
| `commands`    | N        | Shell commands to execute                                |
| `environment` | N        | Step-scoped environment variables                        |
| `secrets`     | N        | Secrets to inject                                        |
| `ruleset`     | N        | Conditions for when this step runs                       |
| `parameters`  | N        | Plugin configuration (injected as `PARAMETER_*` env vars)|
| `pull`        | N        | Image pull policy: `always`, `never`, `not_present`, `on_start` |
| `detach`      | N        | Run container in background (like a service)             |
| `report_as`   | N        | Custom commit status context (max 10 per pipeline)       |
| `id_request`  | N        | Request an OIDC ID token                                 |

## The Workspace

Vela clones your repository into a workspace directory at `/vela/src/<source>/<org>/<repo>`. All steps share this workspace via a mounted volume, so files created in one step are available in the next.

The clone step is injected automatically. You can disable it:

```yaml
metadata:
  clone: false
```

## Image Pull Policies

The `pull` key controls when Docker images are fetched:

| Value         | Behavior                                          |
|---------------|---------------------------------------------------|
| `not_present` | Pull only if not cached locally (default)         |
| `always`      | Always pull, even if cached                       |
| `never`       | Never pull, fail if not cached                    |
| `on_start`    | Pull at container start time                      |

For reproducible builds, use `pull: always` on images with mutable tags like `latest`.

## Metadata

The `metadata` block controls compiler behavior:

```yaml
metadata:
  clone: true          # inject clone step (default: true)
  render_inline: false # for inline template rendering
  auto_cancel:         # cancel superseded builds
    pending: true      # cancel pending builds (default when auto_cancel is set)
    running: false     # cancel running builds
    default_branch: false # include default branch pushes
```

Auto-cancel is useful for busy branches. When enabled, a new push to the same branch cancels pending (and optionally running) builds for that branch.

## Global Environment

Set environment variables available to all steps, services, and secrets:

```yaml
environment:
  GOOS: linux
  CGO_ENABLED: "0"

steps:
  - name: build
    image: golang:1.23-alpine
    commands:
      - go build -o app .
```

Control which container types receive global environment via metadata:

```yaml
metadata:
  environment: [steps, services, secrets]
```

## Style Conventions

### Use simple, literal step names

Name steps after what they do: `test`, `build`, `lint`, `deploy`, `publish`. Avoid clever or compound names like `run-all-unit-and-integration-tests` or `build-and-push-docker-image`. Short names are easier to scan in the UI and in build logs.

```yaml
# Good
- name: test
- name: lint
- name: build
- name: publish
- name: deploy

# Avoid
- name: run-unit-tests-and-linting
- name: build-docker-image-and-push-to-registry
```

### Avoid YAML anchors

Do not use YAML anchors (`&anchor`, `*anchor`, `<<: *merge`). Anchors create indirection that requires backtracking to the anchor definition to understand what a step actually does. They also cause problems with Vela's YAML parser (see the vela-troubleshooting skill for v0.26+ anchor issues).

Prefer explicit repetition instead. Repeated blocks are easier for agents and modern editors with multi-cursor to create and maintain, and every step is self-contained and readable without jumping around the file.

```yaml
# Avoid -- requires backtracking to understand each step
base: &base
  image: golang:1.23-alpine
  pull: always

steps:
  - name: test
    <<: *base
    commands:
      - go test ./...
  - name: build
    <<: *base
    commands:
      - go build -o app .

# Prefer -- each step is self-contained and readable
steps:
  - name: test
    image: golang:1.23-alpine
    pull: always
    commands:
      - go test ./...
  - name: build
    image: golang:1.23-alpine
    pull: always
    commands:
      - go build -o app .
```

## Examples

### Example: Minimal Go Pipeline

```yaml
version: "1"

steps:
  - name: test
    image: golang:1.23-alpine
    commands:
      - go test ./...
```

### Example: Multi-Step Build and Deploy

```yaml
version: "1"

environment:
  CGO_ENABLED: "0"
  GOOS: linux

steps:
  - name: test
    image: golang:1.23-alpine
    commands:
      - go test ./...

  - name: build
    image: golang:1.23-alpine
    commands:
      - go build -o app .

  - name: publish
    image: target/vela-kaniko:latest
    pull: always
    ruleset:
      event: push
      branch: main
    parameters:
      registry: index.docker.io
      repo: index.docker.io/myorg/myapp
```

### Example: Pipeline with Auto-Cancel

```yaml
version: "1"

metadata:
  auto_cancel:
    running: true

steps:
  - name: test
    image: node:22-alpine
    commands:
      - npm ci
      - npm test
```

## Pitfalls

- Vela pipelines support two execution models -- `steps` (sequential) and `stages` (parallel) -- but they are mutually exclusive at the compiler level. Including both causes a compile error because the compiler cannot determine which execution model to use.
- The `version` key is how the Vela compiler identifies which schema to apply. Without `version: "1"`, the compiler has no schema to work with and rejects the pipeline outright.
- Docker image tags like `latest` or `v1` are mutable -- the image behind the tag can change at any time. Workers cache images locally, so without `pull: always`, your step may run a stale cached image that no longer matches what the registry has. Use `pull: always` or pin to a digest for critical steps.
- Setting `clone: false` tells Vela to skip its automatic clone step, so no code is checked out into the workspace. Unless you provide your own clone logic, every subsequent step runs against an empty directory and commands expecting source files will fail.
- YAML's type system automatically interprets bare values like `0`, `1`, `true`, and `false` as integers or booleans rather than strings. Environment variables need to be strings, so wrap these values in quotes (e.g., `CGO_ENABLED: "0"`) to prevent unexpected type coercion.
- YAML anchors (`&name`, `*name`, `<<: *merge`) introduce indirection that makes pipelines harder to read, review, and debug. Vela's v0.26+ parser is also stricter about anchors -- duplicate merge keys and anchor parameter collisions cause compile errors. Write each step explicitly instead. The repetition is trivial for agents and multi-cursor editors to manage, and every step remains self-contained.

## Quick Reference

```yaml
version: "1"

metadata:
  clone: true
  auto_cancel:
    running: true

environment:
  KEY: value

steps:
  - name: step-name        # required, unique
    image: org/image:tag    # required, Docker image
    pull: not_present       # always | never | not_present | on_start
    commands:               # shell commands
      - echo "hello"
    environment:            # step-scoped vars
      FOO: bar
    secrets: [my_secret]    # inject secrets
    ruleset:                # conditional execution
      event: push
      branch: main
    parameters:             # plugin config -> PARAMETER_*
      key: value
    detach: false           # background mode
    report_as: my-check     # custom commit status
```
