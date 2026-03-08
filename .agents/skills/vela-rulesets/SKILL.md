---
name: vela-rulesets
description: "Conditional step execution in Vela: rulesets, if/unless syntax, event scoping (push, pull_request:opened, tag, deployment), branch/path filtering, status rules, and the continue key."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Use rulesets to control which steps run in a Vela build. Attach a `ruleset:` block to any step to gate execution on branch, event, path changes, status, and other build metadata.

There are two categories of rules, and understanding the difference is critical:

- **Compile-time rules** (`branch`, `event`, `path`, `comment`, `tag`, `target`, `repo`, `label`): Evaluated on the server before the pipeline reaches the worker. Steps that fail compile-time rules are **removed entirely** from the pipeline.
- **Runtime rules** (`status`): Evaluated during execution on the worker. The step remains in the pipeline but may be skipped based on the build's current status.

## Rule Types

### Compile-Time Rules

| Rule       | Description                                  | Example Values                    |
|------------|----------------------------------------------|-----------------------------------|
| `branch`   | Branch name                                  | `main`, `release/*`              |
| `event`    | Webhook event (with optional action)         | `push`, `pull_request:opened`    |
| `path`     | Files changed in the commit                  | `src/**`, `*.go`, `README.md`    |
| `tag`      | Git tag reference                            | `v1.*`, `release-*`             |
| `target`   | Deployment or schedule target                | `production`, `staging`          |
| `comment`  | PR comment body                              | `"run build"`                    |
| `repo`     | Repository name                              | `myorg/myrepo`, `myorg/*`       |
| `label`    | PR label                                     | `enhancement`, `bug`            |
| `instance` | FQDN of the Vela server                      | `https://vela.example.com`      |

### Runtime Rules

| Rule     | Description                | Example Values          |
|----------|----------------------------|-------------------------|
| `status` | Current build status       | `success`, `failure`   |

### Eval Rules

The `eval` key uses [expr](https://expr-lang.org/) expressions for complex conditions:

```yaml
ruleset:
  eval: "VELA_BUILD_AUTHOR == 'Octocat'"
```

Eval can be combined with other rules -- all must pass for the step to run.

## Operators and Matchers

### Operator: `and` vs `or`

By default, all rules within a ruleset use **`and`** -- every rule must match:

```yaml
ruleset:
  branch: main
  event: push
  # Step runs only on push events to main
```

Switch to `or` to run when **any** rule matches:

```yaml
ruleset:
  operator: or
  branch: main
  event: tag
  # Step runs on any push to main OR any tag event
```

### Matcher: `filepath` vs `regexp`

The default matcher is `filepath` (glob-style). Switch to `regexp` for regex patterns:

```yaml
ruleset:
  matcher: regexp
  branch: "release-\\d+"
  # Matches release-1, release-42, etc.
```

## if / unless Syntax

For explicit control, use `if:` (run when all match) or `unless:` (skip when any match):

```yaml
# Run only on push to main
ruleset:
  if:
    branch: main
    event: push
```

```yaml
# Skip on pushes to main
ruleset:
  unless:
    branch: main
    event: push
```

The `if:`/`unless:` syntax is equivalent to the shorthand top-level rules but makes intent clearer. Use either style, but do not mix them in the same ruleset -- the compiler cannot resolve the ambiguity when both forms are present.

## Event Scoping

Events support action scoping with `event:action` syntax:

| Event          | Available Actions                                       |
|----------------|---------------------------------------------------------|
| `push`         | (no actions)                                            |
| `pull_request` | `opened`, `synchronize`, `reopened`, `edited`, `labeled`, `unlabeled` |
| `comment`      | `created`, `edited`                                     |
| `deployment`   | `created`                                               |
| `tag`          | (no actions)                                            |

Default expansions when no action is specified:

- `pull_request` = `pull_request:opened` + `pull_request:synchronize` + `pull_request:reopened`
- `comment` = `comment:created` + `comment:edited`
- `deployment` = `deployment:created`

Use wildcard for all actions: `pull_request*`

```yaml
ruleset:
  event: pull_request*  # all PR actions including edited, labeled, unlabeled
```

## The `continue` Key

By default, if a step fails, the entire build fails. Set `continue: true` to allow the build to continue past a failed step:

```yaml
steps:
  - name: lint
    image: golangci/golangci-lint:v1-alpine
    ruleset:
      continue: true
    commands:
      - golangci-lint run
```

This is useful for non-blocking checks like linting or optional notifications.

## Compile-Time Pruning in Stages

When using stages, compile-time rules can cause entire stages to be pruned if all steps within them are removed. "Pruning" means the stage is deleted from the compiled pipeline entirely -- it never reaches the worker and disappears from the `needs:` dependency graph, which can unblock stages that were waiting on it.

See the vela-stages skill for detailed examples of this behavior.

## Examples

### Example: Standard Branch + Event Gating

```yaml
steps:
  - name: test
    image: golang:1.23-alpine
    commands:
      - go test ./...

  - name: deploy
    image: myorg/deployer:latest
    ruleset:
      event: push
      branch: main
    commands:
      - ./deploy.sh
```

### Example: Path-Based Execution

```yaml
steps:
  - name: backend tests
    image: golang:1.23-alpine
    ruleset:
      path: ["backend/**", "go.mod", "go.sum"]
    commands:
      - go test ./...

  - name: frontend tests
    image: node:22-alpine
    ruleset:
      path: ["frontend/**", "package.json"]
    commands:
      - npm test
```

### Example: Failure Notification

```yaml
steps:
  - name: test
    image: golang:1.23-alpine
    commands:
      - go test ./...

  - name: notify on failure
    image: target/vela-slack:latest
    ruleset:
      status: failure
      continue: true
    parameters:
      text: "Build failed for ${VELA_REPO_FULL_NAME}"
```

### Example: PR Label Gating

```yaml
steps:
  - name: deploy preview
    image: myorg/deployer:latest
    ruleset:
      event: ["pull_request:labeled"]
      label: ["deploy-preview"]
    commands:
      - ./deploy-preview.sh
```

### Example: Eval with Expr

```yaml
steps:
  - name: admin-only
    image: alpine:3
    ruleset:
      eval: "VELA_BUILD_AUTHOR == 'admin-user'"
    commands:
      - echo "running admin task"

  - name: prefix-match
    image: alpine:3
    ruleset:
      eval: "hasPrefix(VELA_BUILD_BRANCH, 'release/')"
    commands:
      - echo "release branch detected"
```

## Pitfalls

- The `status` rule is evaluated at runtime on the worker, which means it survives compile-time pruning on its own. However, if a step also has compile-time rules (like `branch` or `event`) that do not match, the step is removed from the pipeline entirely before the worker ever sees it -- and the `status` rule never gets a chance to run. In stages, this can cascade: if all steps in a stage are pruned, the entire stage disappears from the dependency graph.
- Plain `pull_request` expands to only three actions: `opened`, `synchronize`, and `reopened`. Actions like `edited`, `labeled`, and `unlabeled` are excluded. If you need a step to respond to all PR activity, use `pull_request*` with the wildcard to capture every action type.
- The `path` rule compares against the list of changed files included in the webhook payload. Only `push` and `pull_request` events include this file change data. For other event types (like `tag` or `deployment`), the changed file list is empty, so `path` rules will never match.
- The top-level rule syntax (e.g., `ruleset: branch: main`) and the explicit `if:`/`unless:` syntax are two ways of expressing the same thing. Mixing them in a single ruleset creates ambiguity the compiler cannot resolve. Choose one style per ruleset.
- When using `matcher: regexp`, remember that YAML string parsing happens before the regex engine sees the pattern. A single backslash in YAML is an escape character, so regex patterns like `\d+` need double-escaping: `"release-\\d+"`. Without the extra backslash, YAML consumes it and the regex receives `d+` instead.
- The `continue: true` flag controls what happens after a step fails -- it tells Vela to proceed with the remaining steps rather than halting the build. It has no effect on whether the step runs in the first place; that is still governed entirely by the ruleset.

## Quick Reference

```yaml
ruleset:
  # Compile-time rules
  branch: [main, release/*]
  event: [push, pull_request]
  path: ["src/**", "*.go"]
  tag: [v1.*]
  target: [production]
  comment: ["run build"]
  repo: ["myorg/*"]
  label: [enhancement]

  # Runtime rules
  status: [success, failure]

  # Expr evaluation
  eval: "VELA_BUILD_AUTHOR == 'octocat'"

  # Controls
  continue: true         # don't fail build on step failure
  operator: and          # and | or (default: and)
  matcher: filepath      # filepath | regexp (default: filepath)

  # Explicit form (alternative to top-level rules)
  if:
    branch: main
    event: push
  unless:
    branch: main
    event: push

# Event action scoping
event: pull_request:opened
event: pull_request*          # wildcard for all actions
event: comment:created
event: deployment:created
```
