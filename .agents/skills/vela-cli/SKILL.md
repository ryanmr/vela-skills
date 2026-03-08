---
name: vela-cli
description: "Pipeline validation, repo management, secret CRUD, deployments, and build inspection via the `vela` CLI. Covers authentication, webhook checks, schedules, and log retrieval."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Use the `vela` CLI to validate pipelines locally, manage secrets, trigger deployments, inspect builds, and administer repositories. The CLI reads configuration from a local config file (generated via `vela generate config`) and can also be driven entirely by flags or environment variables.

## Authentication

Before using the CLI, authenticate with your Vela server:

```sh
# Interactive login (opens browser for OAuth)
vela login

# Or generate a config file
vela generate config --api.addr https://vela.example.com --api.token <token>
```

The config file stores your server address and token so you don't need to pass them on every command. View your config:

```sh
vela view config
```

## Pipeline Validation

Validate `.vela.yml` syntax locally without triggering a build:

```sh
# Validate the pipeline in the current directory
vela validate pipeline

# Validate a specific file
vela validate pipeline --file path/to/.vela.yml

# Validate with template expansion (requires GitHub token for remote templates)
vela validate pipeline --template --compiler.github.token <token>

# Validate with a local template file substituted for a remote source
vela validate pipeline --template --template-file name:path/to/template.yml

# Validate remotely against the Vela server (checks server-side compilation)
vela validate pipeline --remote --org MyOrg --repo MyRepo

# Validate with specific build context (for ruleset testing)
vela validate pipeline --event push --branch main
vela validate pipeline --event pull_request --branch feature-1
vela validate pipeline --tag v1.0.0 --event tag
```

### Validation Parameters for Ruleset Testing

| Flag              | Description                                 |
|-------------------|---------------------------------------------|
| `--event`         | Simulate a build event                      |
| `--branch`        | Simulate a branch                           |
| `--tag`           | Simulate a tag                              |
| `--target`        | Simulate a deployment target                |
| `--status`        | Expected build status (default: `success`)  |
| `--file-changeset`| Simulate changed files for path rulesets    |
| `--comment`       | Simulate a PR comment                       |

## Pipeline Generation

Generate a starter pipeline:

```sh
vela generate pipeline
```

## Repository Management

### Enable a Repo

```sh
vela add repo --org MyOrg --repo MyRepo
```

### View Repo Settings

```sh
vela view repo --org MyOrg --repo MyRepo
```

### Update Repo Settings

```sh
# Change build limit
vela update repo --org MyOrg --repo MyRepo --build.limit 15

# Change build timeout (in minutes)
vela update repo --org MyOrg --repo MyRepo --timeout 60
```

### Repair a Repo

Recreates the webhook with a valid signature. Use when builds stop appearing:

```sh
vela repair repo --org MyOrg --repo MyRepo
```

Requires admin access on the repository.

### Change Repo Ownership

If the original repo enabler's account is suspended:

```sh
vela chown repo --org MyOrg --repo MyRepo
```

### Sync Repos

```sh
vela sync repo --org MyOrg --repo MyRepo
```

## Secret Management

See the vela-secrets skill for pipeline-side secret declarations and scoping rules.

### Add a Secret

```sh
# Repo secret
vela add secret --secret.engine native --secret.type repo \
  --org MyOrg --repo MyRepo --name my_secret --value "s3cret"

# Org secret
vela add secret --secret.engine native --secret.type org \
  --org MyOrg --name my_secret --value "s3cret"

# Shared secret
vela add secret --secret.engine native --secret.type shared \
  --org MyOrg --team my-team --name my_secret --value "s3cret"

# From a file
vela add secret --secret.engine native --secret.type repo \
  --org MyOrg --repo MyRepo --name my_cert --value @/path/to/cert.pem

# Bulk add from YAML
vela add secret -f secrets.yml
```

### View/List Secrets

```sh
# List repo secrets
vela get secrets --secret.engine native --secret.type repo \
  --org MyOrg --repo MyRepo

# View a specific secret (shows metadata, not value)
vela view secret --secret.engine native --secret.type repo \
  --org MyOrg --repo MyRepo --name my_secret
```

### Update a Secret

```sh
vela update secret --secret.engine native --secret.type repo \
  --org MyOrg --repo MyRepo --name my_secret --value "new_value"
```

### Remove a Secret

```sh
vela remove secret --secret.engine native --secret.type repo \
  --org MyOrg --repo MyRepo --name my_secret
```

## Build Management

```sh
# List recent builds
vela get builds --org MyOrg --repo MyRepo

# View a specific build
vela view build --org MyOrg --repo MyRepo --build 42

# Restart a build
vela restart build --org MyOrg --repo MyRepo --build 42

# Cancel a build
vela cancel build --org MyOrg --repo MyRepo --build 42

# Approve a pending build
vela approve build --org MyOrg --repo MyRepo --build 42

# View build logs
vela get logs --org MyOrg --repo MyRepo --build 42
vela view log --org MyOrg --repo MyRepo --build 42 --step 1
```

## Deployments

Trigger a deployment event. See the vela-deployments skill for pipeline-side deployment configuration.

```sh
# Basic deployment
vela add deployment --org MyOrg --repo MyRepo --target production

# With a specific ref
vela add deployment --org MyOrg --repo MyRepo --target staging --ref dev

# With parameters
vela add deployment --org MyOrg --repo MyRepo --target production \
  --parameter 'region=us-west' --parameter 'replicas=3'

# With a specific tag
vela add deployment --org MyOrg --repo MyRepo \
  --ref 'refs/tags/v1.2.3' --target production

# List deployments
vela get deployments --org MyOrg --repo MyRepo
```

## Webhook Management

Inspect webhook deliveries when debugging missing or failed builds. See the vela-troubleshooting skill for a broader debugging workflow.

```sh
# List recent hooks
vela get hooks --org MyOrg --repo MyRepo

# View a specific hook
vela view hook --org MyOrg --repo MyRepo --hook 1
```

## Schedule Management

```sh
# Add a scheduled build
vela add schedule --org MyOrg --repo MyRepo --name nightly \
  --entry "0 0 * * *" --branch main

# List schedules
vela get schedules --org MyOrg --repo MyRepo

# Remove a schedule
vela remove schedule --org MyOrg --repo MyRepo --name nightly
```

## Examples

### Example: Full Validation Workflow

```sh
# Quick local syntax check
vela validate pipeline

# Check with template expansion using local template
vela validate pipeline --template --template-file deploy:./templates/deploy.yml

# Check how it compiles for a specific event
vela validate pipeline --event push --branch main

# Full remote validation against the server
vela validate pipeline --remote --org MyOrg --repo MyRepo
```

### Example: Secret Rotation

```sh
# Update an existing secret
vela update secret --secret.engine native --secret.type repo \
  --org MyOrg --repo MyRepo --name api_key --value "new-key-value"

# Verify it was updated (shows last updated timestamp)
vela view secret --secret.engine native --secret.type repo \
  --org MyOrg --repo MyRepo --name api_key
```

## Pitfalls

- The `vela validate pipeline` command defaults to looking for `.vela.yml` in the current working directory. If you run it from a different directory, it either fails to find the file or validates the wrong one. You can override this with `--path` or `--file`, but the simplest fix is to `cd` into the repo root first.
- Secret commands require `--secret.engine native --secret.type repo` (or `org`/`shared`) because Vela supports multiple secret backends and scopes. Without these flags, the CLI does not know which secret store or permission boundary you intend to target, so it will either error out or operate on an unintended scope.
- Shell metacharacters in secret values (quotes, backslashes, dollar signs) get interpreted by your shell before the CLI ever sees them. This means the value stored in Vela may silently differ from what you typed. Wrapping values in single quotes helps, and backslashes need triple-escaping (`\\\`) because they pass through multiple layers of interpretation.
- The `vela repair repo` command recreates the webhook with a fresh signature, which requires admin-level GitHub permissions on the repository. If you only have write access, the API call will be rejected -- you will need a repo admin to run it for you.
- The CLI can infer `--org` and `--repo` from your config file or git remote context, but this inference can be wrong if you have multiple remotes or a stale config. Passing these flags explicitly removes the guesswork and makes scripts portable across environments.

## Quick Reference

```sh
# Authentication
vela login
vela generate config --api.addr <url> --api.token <token>

# Pipeline
vela validate pipeline
vela validate pipeline --template --template-file name:path
vela validate pipeline --remote --org <org> --repo <repo>
vela generate pipeline

# Repository
vela add repo --org <org> --repo <repo>
vela view repo --org <org> --repo <repo>
vela update repo --org <org> --repo <repo> --build.limit <n>
vela repair repo --org <org> --repo <repo>
vela chown repo --org <org> --repo <repo>

# Secrets
vela add secret --secret.engine native --secret.type <type> --name <n> --value <v>
vela get secrets --secret.engine native --secret.type <type>
vela view secret --secret.engine native --secret.type <type> --name <n>
vela update secret --secret.engine native --secret.type <type> --name <n> --value <v>
vela remove secret --secret.engine native --secret.type <type> --name <n>

# Builds
vela get builds --org <org> --repo <repo>
vela view build --org <org> --repo <repo> --build <n>
vela restart build --org <org> --repo <repo> --build <n>
vela cancel build --org <org> --repo <repo> --build <n>
vela approve build --org <org> --repo <repo> --build <n>

# Deployments
vela add deployment --org <org> --repo <repo> --target <env>
vela get deployments --org <org> --repo <repo>

# Hooks
vela get hooks --org <org> --repo <repo>

# Schedules
vela add schedule --org <org> --repo <repo> --name <n> --entry "<cron>"
```
