---
name: vela-deployments
description: "Deployment targets, parameters, CLI triggers, and DEPLOYMENT_PARAMETER_* variables in Vela. Gating steps to deployment events and the deployment UI form."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Trigger deployment workflows in Vela by sending a deployment event via CLI, API, or UI. Define deployment targets, pass custom parameters, and gate steps to specific deployment contexts using rulesets. Vela integrates with your SCM's deployment system (e.g., GitHub Deployments) and passes custom parameters as environment variables to your pipeline.

## Enabling Deployments

Deployments must be enabled on the repository. Check your repo settings in the UI or via CLI:

```sh
vela view repo --org MyOrg --repo MyRepo
```

The `allow_deploy` setting must be `true`.

## Triggering Deployments

### Via CLI

```sh
# Basic deployment to production
vela add deployment --org MyOrg --repo MyRepo --target production

# Deploy a specific branch
vela add deployment --org MyOrg --repo MyRepo --target staging --ref dev

# Deploy a specific commit
vela add deployment --org MyOrg --repo MyRepo --target production \
  --ref 48afb5bdc41ad69bf22588491333f7cf71135163

# Deploy a specific tag
vela add deployment --org MyOrg --repo MyRepo --target production \
  --ref 'refs/tags/v1.2.3'

# Deploy with custom parameters
vela add deployment --org MyOrg --repo MyRepo --target production \
  --parameter 'region=us-west' --parameter 'replicas=3'

# Deploy with a description
vela add deployment --org MyOrg --repo MyRepo --target production \
  --description 'Deploying hotfix for issue #42'
```

### Via UI

Navigate to the repository in the Vela UI and use the "Add Deployment" page. If deployment configuration is defined in the pipeline, the UI will render form fields with validation.

## Deployment Environment Variables

When a deployment event triggers a build, these additional variables are available:

| Variable                    | Example        | Description                         |
|-----------------------------|----------------|-------------------------------------|
| `VELA_BUILD_EVENT`          | `deployment`   | Event type                          |
| `VELA_BUILD_TARGET`         | `production`   | Deployment target                   |
| `VELA_DEPLOYMENT`           | `production`   | Deployment target (alias)           |
| `VELA_DEPLOYMENT_NUMBER`    | `12345`        | Deployment ID from SCM              |
| `DEPLOYMENT_PARAMETER_*`    | varies         | Custom parameters (uppercased key)  |

Custom parameters passed via `--parameter key=value` become `DEPLOYMENT_PARAMETER_KEY` environment variables.

## Pipeline Configuration

### Gating Steps to Deployments

Use rulesets to run steps only on deployment events (see the vela-rulesets skill for full ruleset syntax):

```yaml
steps:
  - name: deploy
    image: myorg/deployer:latest
    ruleset:
      event: deployment
    commands:
      - ./deploy.sh
```

### Target-Specific Steps

Gate steps to specific deployment targets:

```yaml
steps:
  - name: deploy to staging
    image: myorg/deployer:latest
    ruleset:
      event: deployment
      target: staging
    commands:
      - ./deploy.sh --env staging

  - name: deploy to production
    image: myorg/deployer:latest
    ruleset:
      event: deployment
      target: production
    commands:
      - ./deploy.sh --env production
```

### Using Deployment Parameters

Access custom parameters as environment variables:

```yaml
steps:
  - name: deploy
    image: myorg/deployer:latest
    ruleset:
      event: deployment
    commands:
      # Parameters passed as --parameter region=us-west --parameter replicas=3
      - echo "Deploying to region $${DEPLOYMENT_PARAMETER_REGION}"
      - echo "Replicas: $${DEPLOYMENT_PARAMETER_REPLICAS}"
      - ./deploy.sh
```

Note the `$${}` escaping -- deployment parameters are runtime variables, not available at compile time. See the vela-environment skill for full details on the `$${}` escape syntax and compile-time vs runtime variable handling.

## The `deployment:` Configuration Block

The optional `deployment:` key in your pipeline provides guardrails and UI form generation:

### Targets

Restrict which targets are allowed:

```yaml
deployment:
  targets: [dev, staging, production]
```

If a user tries to deploy to a target not in this list, the deployment is blocked.

### Parameters

Define expected parameters with types, validation, and descriptions:

```yaml
deployment:
  targets: [dev, staging, production]
  parameters:
    region:
      description: Region to deploy to
      required: true
      options: [us-west, us-east, eu-west]
    replicas:
      description: Number of replicas
      type: int
      required: false
      min: 1
      max: 10
    run_tests:
      description: Run integration tests before deploy
      type: bool
```

Parameter type options:
- String (default): any text value, optionally restricted by `options`
- `int` / `integer` / `number`: numeric value with optional `min`/`max`
- `bool` / `boolean`: true/false toggle

These configurations generate form validation in the UI when users visit the "Add Deployment" page.

## Examples

### Example: Full Deployment Pipeline

```yaml
version: "1"

deployment:
  targets: [staging, production]
  parameters:
    region:
      description: Deployment region
      required: true
      options: [us-west, us-east]

secrets:
  - name: deploy_key
    key: myorg/myrepo/deploy_key
    engine: native
    type: repo          # See the vela-secrets skill for secret configuration details

steps:
  - name: test
    image: golang:1.23-alpine
    commands:
      - go test ./...

  - name: build
    image: golang:1.23-alpine
    commands:
      - go build -o app .

  - name: deploy
    image: myorg/deployer:latest
    secrets: [deploy_key]
    ruleset:
      event: deployment
    commands:
      - ./deploy.sh --target $${VELA_DEPLOYMENT} --region $${DEPLOYMENT_PARAMETER_REGION}

  - name: notify
    image: target/vela-slack:latest
    secrets: [slack_webhook]
    ruleset:
      event: deployment
    parameters:
      text: "Deployed ${VELA_REPO_FULL_NAME} to $${VELA_DEPLOYMENT}"
```

### Example: Staged Rollout

```yaml
version: "1"

deployment:
  targets: [canary, production]

steps:
  - name: canary deploy
    image: myorg/deployer:latest
    ruleset:
      event: deployment
      target: canary
    commands:
      - ./deploy.sh --canary

  - name: full deploy
    image: myorg/deployer:latest
    ruleset:
      event: deployment
      target: production
    commands:
      - ./deploy.sh --full
```

## Pitfalls

- Deployment parameters like `DEPLOYMENT_PARAMETER_REGION` don't exist at pipeline compile time -- they're injected at runtime when the deployment actually executes. If you reference them with single-dollar syntax (`${DEPLOYMENT_PARAMETER_REGION}`), Vela's compiler tries to substitute them during compilation, finds nothing, and silently replaces them with an empty string. The double-dollar syntax (`$${DEPLOYMENT_PARAMETER_REGION}`) tells the compiler to leave it alone and let the shell resolve it at runtime.
- The `allow_deploy` setting on a repository defaults to off. When it's disabled, Vela silently ignores deployment webhook events, so your `vela add deployment` command will appear to succeed (it creates the deployment in your SCM) but no Vela build is triggered. Check repo settings if deployments seem to vanish into the void.
- The `target` ruleset field only has meaning for `deployment` and `schedule` events. If you write a ruleset with `target: production` but omit `event: deployment`, the step will match on push and PR events too (where `target` is simply ignored), which is almost certainly not what you want. Always pair `target` with its corresponding event.
- When you omit `--ref`, the deployment defaults to the tip of your default branch at that moment. This is risky because someone else's merge could land between when you decided to deploy and when you ran the command. Specifying a branch, tag, or commit SHA makes the deployment deterministic and auditable.
- Deployment parameters are stored in your SCM's deployment record and are visible to anyone with repository access. They're designed for configuration values like region or replica count, not credentials. Sensitive values should go through Vela's secrets system, which has access controls, event restrictions, and never exposes values in logs or API responses.

## Quick Reference

```sh
# Trigger deployments
vela add deployment --org <org> --repo <repo> --target <env>
vela add deployment --org <org> --repo <repo> --target <env> --ref <branch|tag|sha>
vela add deployment --org <org> --repo <repo> --target <env> --parameter 'key=value'

# List deployments
vela get deployments --org <org> --repo <repo>
```

```yaml
# Pipeline deployment config
deployment:
  targets: [dev, staging, production]
  parameters:
    name:
      description: "Description"
      type: string            # string (default) | int | bool
      required: true
      options: [a, b, c]      # restrict to allowed values
      min: 1                  # int only
      max: 10                 # int only

# Ruleset for deployment steps
ruleset:
  event: deployment
  target: production

# Runtime variables (escape with $$)
# $${VELA_DEPLOYMENT}              - target name
# $${VELA_DEPLOYMENT_NUMBER}       - deployment ID
# $${DEPLOYMENT_PARAMETER_<KEY>}   - custom parameter
```
