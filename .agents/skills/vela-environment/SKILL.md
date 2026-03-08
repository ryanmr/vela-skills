---
name: vela-environment
description: "Environment variables, ${VAR} substitution, $${} escaping, VELA_* built-ins, VELA_OUTPUTS for inter-step data, and variable scoping (global, step, compile-time vs runtime) in Vela pipelines."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Use environment variables and the `${VAR}` substitution syntax to make Vela pipelines dynamic. Set variables at three scopes -- global (pipeline-level), step-level, and via secrets (see the vela-secrets skill for secret scoping). Pass data between steps with `VELA_OUTPUTS`.

The critical distinction: `${VAR}` is resolved **at compile time** on the server, while `$${VAR}` is resolved **at runtime** in the container. Mixing these up is the most common source of unexpected values.

## Scoping

### Global Environment

Variables declared at the pipeline level are injected into steps, services, and secret containers by default:

```yaml
environment:
  GOOS: linux
  CGO_ENABLED: "0"

steps:
  - name: build
    image: golang:1.23-alpine
    commands:
      - echo $GOOS  # prints "linux"
```

Control which container types receive global environment:

```yaml
metadata:
  environment: [steps, services]  # exclude secrets containers
```

### Step-Level Environment

Variables declared on a step override global values for that step only:

```yaml
environment:
  TARGET: default

steps:
  - name: step-a
    image: alpine:3
    environment:
      TARGET: custom
    commands:
      - echo $TARGET  # prints "custom"

  - name: step-b
    image: alpine:3
    commands:
      - echo $TARGET  # prints "default"
```

Both map and array syntax are supported:

```yaml
# Map syntax (preferred)
environment:
  DB_NAME: vela

# Array syntax
environment:
  - DB_NAME=vela
```

## Substitution Syntax

Vela evaluates `${VAR}` expressions **at compile time** before the YAML is parsed. This means substitution happens on the Vela server before your pipeline reaches a worker.

### Common Operations

| Syntax                         | Description                              | Example                    |
|--------------------------------|------------------------------------------|----------------------------|
| `${VAR}`                       | Simple expansion                         | `${VELA_REPO_FULL_NAME}`  |
| `${VAR:-default}`              | Default if unset/null (does not assign)  | `${TAG:-latest}`          |
| `${VAR:=default}`              | Default if unset/null (assigns)          | `${TAG:=latest}`          |
| `${VAR:position}`              | Substring from position                  | `${VELA_BUILD_COMMIT:0}`  |
| `${VAR:position:length}`       | Substring with length                    | `${VELA_BUILD_COMMIT:0:8}`|
| `${VAR^^}`                     | Uppercase all                            | `${BRANCH^^}`             |
| `${VAR,,}`                     | Lowercase all                            | `${BRANCH,,}`             |
| `${VAR/old/new}`               | Replace first match                      | `${BRANCH/feature-/}`     |
| `${VAR//old/new}`              | Replace all matches                      | `${PATH//old/new}`        |
| `${#VAR}`                      | Length of value                           | `${#VELA_BUILD_COMMIT}`   |

### Escaping Substitution

If you want `${VAR}` to be evaluated at **runtime** (inside the container shell) rather than at compile time, escape with double `$$`:

```yaml
steps:
  - name: example
    image: alpine:3
    commands:
      # Compile-time: resolved by Vela server before execution
      - echo ${VELA_REPO_FULL_NAME}
      # Runtime: resolved inside the container shell
      - echo $${VELA_BUILD_STATUS}
```

This is critical for variables that aren't accurate at compile time. Compile-time values are stale placeholders -- the real values only exist once the build is running on a worker:

| Variable                   | Compile Time | Runtime          |
|----------------------------|-------------|------------------|
| `VELA_BUILD_STARTED`       | `0`         | `1556730001`     |
| `VELA_BUILD_STATUS`        | `pending`   | `running`        |
| `VELA_BUILD_HOST`          | `''`        | `vela-worker-42` |
| `VELA_BUILD_RUNTIME`       | `''`        | `docker`         |
| `VELA_BUILD_DISTRIBUTION`  | `''`        | `linux`          |
| `VELA_BUILD_APPROVED_AT`   | `0`         | `1556730001`     |
| `VELA_BUILD_APPROVED_BY`   | `''`        | `Octocat`        |
| `VELA_BUILD_ENQUEUED`      | `0`         | `1556730001`     |

## Built-in Variables

### Always Available

Key variables injected into every container:

| Variable                  | Example Value                          | Description                  |
|---------------------------|----------------------------------------|------------------------------|
| `CI`                      | `true`                                 | Indicates CI environment     |
| `VELA`                    | `true`                                 | Indicates Vela environment   |
| `VELA_BUILD_BRANCH`       | `main`                                 | Source branch                |
| `VELA_BUILD_COMMIT`       | `7fd1a60b01f...`                       | Full commit SHA              |
| `VELA_BUILD_EVENT`        | `push`                                 | Webhook event type           |
| `VELA_BUILD_EVENT_ACTION`  | `created`                             | Webhook event action         |
| `VELA_BUILD_AUTHOR`       | `octocat`                              | Commit author                |
| `VELA_BUILD_NUMBER`       | `1`                                    | Build number                 |
| `VELA_BUILD_LINK`         | `https://vela.example.com/org/repo/1`  | Link to build UI             |
| `VELA_BUILD_MESSAGE`      | `Merge pull request #6`                | Commit message               |
| `VELA_BUILD_REF`          | `refs/heads/main`                      | Git reference                |
| `VELA_BUILD_WORKSPACE`    | `/vela/src/github.com/org/repo`        | Workspace path               |
| `VELA_REPO_FULL_NAME`     | `octocat/hello-world`                  | Org/repo                     |
| `VELA_REPO_ORG`           | `octocat`                              | Organization                 |
| `VELA_REPO_NAME`          | `hello-world`                          | Repository name              |
| `VELA_REPO_BRANCH`        | `main`                                 | Default branch               |
| `VELA_REPO_TOPICS`        | `cloud,security`                       | Comma-separated topics       |
| `VELA_WORKSPACE`          | `/vela/src/github.com/org/repo`        | Workspace path               |
| `VELA_OUTPUTS`            | `/vela/outputs/.env`                   | Dynamic env file path        |
| `VELA_MASKED_OUTPUTS`     | `/vela/outputs/masked.env`             | Masked dynamic env file path |

### Event-Specific Variables

**Pull Request** (`pull_request` and `comment` events):

| Variable                   | Example | Description              |
|----------------------------|---------|--------------------------|
| `VELA_PULL_REQUEST`        | `1`     | PR number                |
| `VELA_PULL_REQUEST_SOURCE` | `dev`   | Source branch            |
| `VELA_PULL_REQUEST_TARGET` | `main`  | Target branch            |

**Tag** events:

| Variable         | Example  | Description |
|------------------|----------|-------------|
| `VELA_BUILD_TAG` | `v1.0.0` | Tag name    |

**Deployment** events:

| Variable                | Example      | Description                  |
|-------------------------|-------------|------------------------------|
| `VELA_DEPLOYMENT`       | `production`| Target environment           |
| `VELA_DEPLOYMENT_NUMBER`| `12345`     | Deployment ID from source    |
| `DEPLOYMENT_PARAMETER_*`| varies      | Custom deployment parameters |

### Step-Only Variables

| Variable             | Description              |
|----------------------|--------------------------|
| `VELA_STEP_NAME`     | Name of the step         |
| `VELA_STEP_NUMBER`   | Step number in pipeline  |
| `VELA_STEP_IMAGE`    | Image used               |
| `VELA_STEP_STATUS`   | Step status              |
| `VELA_STEP_STAGE`    | Stage name (if in stage) |

## Inter-Step Data with VELA_OUTPUTS

Pass data between steps by writing to `$VELA_OUTPUTS`:

```yaml
steps:
  - name: produce
    image: alpine:3
    commands:
      - echo "MY_VALUE=hello-from-step-1" >> $VELA_OUTPUTS

  - name: consume
    image: alpine:3
    commands:
      - echo $MY_VALUE  # prints "hello-from-step-1"
```

For sensitive values, write to `$VELA_MASKED_OUTPUTS` -- values will be masked in logs:

```yaml
steps:
  - name: generate-token
    image: alpine:3
    commands:
      - echo "API_TOKEN=secret123" >> $VELA_MASKED_OUTPUTS

  - name: use-token
    image: alpine:3
    commands:
      - echo $API_TOKEN  # prints *** in logs
```

## Examples

### Example: Short Commit SHA in Image Tag

```yaml
steps:
  - name: build image
    image: target/vela-kaniko:latest
    parameters:
      repo: index.docker.io/myorg/myapp
      tags:
        - ${VELA_BUILD_COMMIT:0:8}
        - latest
```

### Example: Branch-Dependent Defaults

```yaml
steps:
  - name: deploy
    image: myorg/deployer:latest
    environment:
      DEPLOY_ENV: ${VELA_BUILD_BRANCH:-development}
    commands:
      - deploy --env $DEPLOY_ENV
```

### Example: Runtime Variable Usage

```yaml
steps:
  - name: report
    image: alpine:3
    commands:
      # Must escape -- VELA_BUILD_STATUS is not accurate at compile time
      - echo "Build status is $${VELA_BUILD_STATUS}"
```

## Pitfalls

- Vela evaluates `${...}` expressions at compile time on the server, before the pipeline reaches the worker. Since `VELA_BUILD_STATUS` is `pending` at compile time, `${VELA_BUILD_STATUS}` bakes the literal string "pending" into your pipeline. To get the actual runtime value, escape with `$$` so the shell evaluates it: `$${VELA_BUILD_STATUS}`. The same applies to other runtime-only variables like `VELA_BUILD_HOST` and `VELA_BUILD_STARTED`.
- All `${...}` substitution happens on the Vela server before YAML is sent to the worker. If a variable does not exist or has no value at compile time, the expression silently resolves to an empty string -- there is no error or warning. This is why runtime-only variables appear blank when referenced with single-dollar syntax.
- YAML's type system automatically coerces bare values like `true`, `false`, `0`, and `1` into booleans or integers. Environment variables must be strings, so these values need quotes (e.g., `ENABLED: "true"`) to prevent the YAML parser from converting them before Vela sees them.
- The `$VELA_OUTPUTS` file accumulates key-value pairs across commands and steps. Using `>` (overwrite) instead of `>>` (append) replaces the entire file contents, wiping out any previously written variables. Always use `>>` to append.
- Event-specific variables like `VELA_BUILD_TAG` are only populated when the corresponding event triggers the build. On a `push` or `pull_request` event, `VELA_BUILD_TAG` is simply an empty string. Guard any logic that depends on these variables with a ruleset that restricts the step to the appropriate event type.

## Quick Reference

```
Compile-time substitution:     ${VAR}
Runtime (escape):              $${VAR}
Default value:                 ${VAR:-default}
Substring:                     ${VAR:0:8}
Uppercase:                     ${VAR^^}
Lowercase:                     ${VAR,,}
Replace first:                 ${VAR/old/new}
Replace all:                   ${VAR//old/new}
Length:                         ${#VAR}
Inter-step data:               echo "KEY=value" >> $VELA_OUTPUTS
Masked inter-step data:        echo "KEY=value" >> $VELA_MASKED_OUTPUTS
```
