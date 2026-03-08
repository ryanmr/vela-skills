---
name: vela-stages
description: "Parallel execution with Vela stages: the needs dependency system, independent stages for monorepos, and compile-time stage pruning behavior."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Use stages to run groups of steps in parallel. Each stage contains a sequential list of steps, and stages themselves run concurrently unless ordered by `needs:` dependencies.

Stages are more complex than plain `steps` and introduce surprising behavior around compile-time pruning. Use them only when you genuinely need parallel execution. For most pipelines, sequential `steps` are simpler and sufficient. See the vela-pipeline-authoring skill for guidance on choosing between steps and stages.

## Basic Structure

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

In this example, `test` and `lint` run in parallel.

## Stage Keys

| Key           | Required | Type     | Description                                           |
|---------------|----------|----------|-------------------------------------------------------|
| `name`        | Y        | string   | Unique identifier (the YAML key itself)               |
| `steps`       | Y        | []step   | Sequential steps within the stage                     |
| `needs`       | N        | []string | Stages that must complete before this one starts      |
| `independent` | N        | bool     | Continue this stage even if other stages fail         |

## The `needs` Key

Use `needs:` to create dependencies between stages:

```yaml
stages:
  build:
    steps:
      - name: compile
        image: golang:1.23-alpine
        commands:
          - go build -o app .

  test:
    steps:
      - name: unit tests
        image: golang:1.23-alpine
        commands:
          - go test ./...

  deploy:
    needs: [build, test]
    steps:
      - name: deploy app
        image: myorg/deployer:latest
        ruleset:
          event: push
          branch: main
        commands:
          - ./deploy.sh
```

Here `build` and `test` run in parallel. `deploy` waits for both to complete.

**Important:** `needs:` references stages by their name key. Stages without `needs:` run immediately (in parallel with other unblocked stages).

## The `independent` Key

By default, if any stage fails, all subsequent stages are cancelled. Use `independent: true` to isolate a stage from failures in other stages:

```yaml
stages:
  backend:
    independent: true
    steps:
      - name: backend tests
        image: golang:1.23-alpine
        commands:
          - go test ./...

  frontend:
    independent: true
    steps:
      - name: frontend tests
        image: node:22-alpine
        commands:
          - npm test
```

If `backend` fails, `frontend` continues (and vice versa). This is especially useful for monorepo pipelines where independent modules should not block each other.

## Compile-Time Pruning

This is the most important (and surprising) behavior of stages. When Vela compiles a pipeline, it evaluates **compile-time rules** (`branch`, `event`, `path`, `tag`, `target`, `repo`, `comment`) on every step. If all steps in a stage are pruned by compile-time rules, the **entire stage disappears** from the compiled pipeline. See the vela-rulesets skill for details on compile-time vs. runtime rules.

### Pruning Affects `needs:`

When a stage is pruned, it's removed from the `needs:` of other stages. This can cause stages to run earlier than expected:

**Original pipeline:**

```yaml
stages:
  build:
    steps:
      - name: compile
        image: golang:1.23-alpine
        commands:
          - go build .

  deploy:
    needs: [build]
    steps:
      - name: publish image
        image: target/vela-kaniko:latest
        ruleset:
          event: push
          branch: main
        parameters:
          registry: index.docker.io
          repo: index.docker.io/myorg/myapp

  notify:
    needs: [build, deploy]
    steps:
      - name: slack
        image: target/vela-slack:latest
        ruleset:
          status: failure
        parameters:
          text: "Build failed"
```

**On a push to `feature-branch`**, the `deploy` stage is pruned (its only step has `branch: main`). The compiled pipeline becomes:

```yaml
stages:
  build:
    steps:
      - name: compile
        image: golang:1.23-alpine
        commands:
          - go build .

  notify:
    needs: [build]          # deploy was removed from needs
    steps:
      - name: slack
        image: target/vela-slack:latest
        ruleset:
          status: failure
        parameters:
          text: "Build failed"
```

### Runtime Rules Survive Pruning

Steps with only **runtime rules** (like `status: failure`) are NOT pruned at compile time. They stay in the pipeline and are evaluated at runtime. This is why notification steps typically use `status:` rather than compile-time rules.

### The Pruning Trap

Consider this scenario:

```yaml
stages:
  first:
    steps:
      - name: always runs
        image: alpine:3
        commands:
          - echo "done"

  conditional:
    needs: [first]
    steps:
      - name: only on main
        image: alpine:3
        ruleset:
          branch: main
        commands:
          - echo "main only"

  final:
    needs: [conditional]
    steps:
      - name: wrap up
        image: alpine:3
        commands:
          - echo "finished"
```

On a push to `feature-branch`, `conditional` is completely pruned. `final` then has empty `needs: []` and runs **immediately in parallel with `first`** -- not after it.

To avoid this, make `final` depend on stages you know will always exist:

```yaml
  final:
    needs: [first, conditional]
```

Now even if `conditional` is pruned, `final` still waits for `first`.

## Examples

### Example: Parallel Test Matrix

```yaml
version: "1"

stages:
  test-go:
    steps:
      - name: go tests
        image: golang:1.23-alpine
        commands:
          - go test ./...

  test-node:
    steps:
      - name: node tests
        image: node:22-alpine
        commands:
          - npm ci
          - npm test

  deploy:
    needs: [test-go, test-node]
    steps:
      - name: deploy
        image: myorg/deployer:latest
        ruleset:
          event: push
          branch: main
        commands:
          - ./deploy.sh
```

### Example: Monorepo with Independent Stages

```yaml
version: "1"

stages:
  backend:
    independent: true
    steps:
      - name: build backend
        image: golang:1.23-alpine
        ruleset:
          path: ["backend/**", "go.mod", "go.sum"]
        commands:
          - cd backend && go build .

      - name: test backend
        image: golang:1.23-alpine
        ruleset:
          path: ["backend/**", "go.mod", "go.sum"]
        commands:
          - cd backend && go test ./...

  frontend:
    independent: true
    steps:
      - name: build frontend
        image: node:22-alpine
        ruleset:
          path: ["frontend/**", "package.json"]
        commands:
          - cd frontend && npm ci && npm run build

      - name: test frontend
        image: node:22-alpine
        ruleset:
          path: ["frontend/**", "package.json"]
        commands:
          - cd frontend && npm test
```

## Pitfalls

- Stages introduce compile-time pruning, the `needs` dependency graph, and `independent` isolation semantics -- all of which interact in non-obvious ways. If your pipeline runs everything sequentially, plain `steps` give you the same result with none of that complexity. Reach for stages only when you have genuinely independent work that benefits from parallel execution.
- Compile-time pruning does not just remove stages -- it rewrites the `needs` graph of every stage that depended on the pruned one. If a stage's only dependency gets pruned, its `needs` list becomes empty and it runs immediately, potentially in parallel with stages it was supposed to wait for. The fix is to always include at least one dependency you know will survive pruning (like a stage with no compile-time rulesets).
- Stages without a `needs` key are treated as having no dependencies, so Vela schedules them to run immediately and in parallel with every other unblocked stage. There is no implicit ordering based on the YAML position. If stage B must run after stage A, you must explicitly declare `needs: [A]` -- otherwise their execution order is nondeterministic.
- Steps within a stage always execute sequentially, top to bottom -- the parallelism boundary is between stages, not within them. If you need two tasks to run at the same time, put them in separate stages. Placing all steps inside a single stage gives you no parallelism and is identical to a plain `steps` pipeline but with the added overhead of stage semantics.

## Quick Reference

```yaml
version: "1"

stages:
  stage-name:                  # unique identifier
    independent: true          # isolate from other stage failures
    needs: [other-stage]       # wait for dependencies
    steps:                     # sequential within the stage
      - name: step-name
        image: org/image:tag
        commands:
          - echo "hello"

# Pruning rules:
# - Compile-time rules (event, branch, path, tag, target): prune steps before execution
# - If ALL steps in a stage are pruned, the stage disappears
# - Pruned stages are removed from other stages' needs: lists
# - Runtime rules (status): NOT pruned, evaluated at runtime
```
