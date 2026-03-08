---
name: vela-secrets
description: "Secret scopes (repo, org, shared), injection, source/target mapping, PR restrictions, allow_command/allow_substitution, image allowlists, and troubleshooting empty secrets in Vela."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Store sensitive values (API keys, tokens, passwords) and inject them into pipeline containers as environment variables. Manage secrets through the Vela UI, CLI, or API and reference them in pipeline YAML.

There are three scopes of internal secrets (stored in the Vela database via the `native` engine), each with different access patterns and security defaults.

## Secret Scopes

| Scope    | Key Pattern              | Access                           | Who Can Manage      |
|----------|--------------------------|----------------------------------|---------------------|
| `repo`   | `<org>/<repo>/<name>`    | Single repository only           | Repo admins         |
| `org`    | `<org>/<name>`           | Any repo in the organization     | Org admins          |
| `shared` | `<org>/<team>/<name>`    | Any repo (scoped by SCM team)    | Team members        |

### Repo Secrets

Scoped to a single repository. Simplest and most common:

```yaml
secrets:
  - name: docker_password
    key: myorg/myrepo/docker_password
    engine: native
    type: repo
```

### Org Secrets

Available to any repository in the organization:

```yaml
secrets:
  - name: npm_token
    key: myorg/npm_token
    engine: native
    type: org
```

### Shared Secrets

Available across the SCM, scoped to a team. Require a team to exist in your SCM org:

```yaml
secrets:
  - name: deploy_key
    key: myorg/platform-team/deploy_key
    engine: native
    type: shared
```

Both org and shared secrets support **repository allowlists** to restrict access to specific repositories.

## Declaring Secrets in YAML

Every secret you use must be declared in the top-level `secrets:` block with all required fields:

```yaml
secrets:
  - name: docker_password
    key: myorg/myrepo/docker_password
    engine: native
    type: repo
```

All four fields (`name`, `key`, `engine`, `type`) should be explicitly specified.

## Injecting Secrets into Steps

Reference secrets by name in a step's `secrets:` key. They're injected as uppercase environment variables:

```yaml
secrets:
  - name: docker_password
    key: myorg/myrepo/docker_password
    engine: native
    type: repo

steps:
  - name: build image
    image: target/vela-kaniko:latest
    secrets: [docker_password]
    parameters:
      registry: index.docker.io
      repo: index.docker.io/myorg/myapp
    # DOCKER_PASSWORD is available as an env var
```

### Source/Target Mapping

To inject a secret under a different environment variable name, use the source/target syntax:

```yaml
steps:
  - name: custom plugin
    image: myorg/my-plugin:latest
    secrets:
      - source: github_token
        target: PARAMETER_API_TOKEN
```

This is safer than using substitution (`${GITHUB_TOKEN}`) because it avoids exposing the secret value in the compiled pipeline.

## Secret Pull Timing

By default, secrets are fetched at the start of the build (`build_start`). You can defer to step execution time:

```yaml
secrets:
  - name: short_lived_token
    key: myorg/myrepo/short_lived_token
    engine: native
    type: repo
    pull: step_start  # fetch when the step that uses it starts
```

Note: `step_start` is not available on Kubernetes-based workers.

## Security Defaults

Different secret types have different default security settings. Shared secrets have stricter defaults because they have the broadest access scope -- any repo in the SCM org can potentially use them, so tighter controls reduce the blast radius of a misconfiguration:

| Setting              | Repo                  | Org                   | Shared                |
|----------------------|-----------------------|-----------------------|-----------------------|
| Allow Command        | Yes                   | Yes                   | **No**                |
| Allow Substitution   | Yes                   | Yes                   | **No**                |
| Images               | Any                   | Any                   | Any                   |
| Allow Events         | Push, Tag, Deployment | Push, Tag, Deployment | Push, Tag, Deployment |

### Pull Request Restrictions

**Secrets do NOT have `pull_request` events enabled by default.** This is intentional -- PR events can be triggered by users without write access to the repository, which could expose secrets.

If you need secrets in PR builds, enable the `pull_request` event on the secret and consider adopting a build approval policy.

### Allow Command

When set to `false`, the secret is not injected into steps that have a `commands` block or custom `entrypoint`. This limits secrets to plugin-only usage:

```yaml
steps:
  - name: example
    image: alpine:3
    secrets: [no_commands_secret]
    commands:
      - echo $NO_COMMANDS_SECRET  # prints nothing (not injected)
```

### Allow Substitution

When set to `false`, the secret cannot be referenced via `${KEY}` substitution syntax. This prevents compile-time exposure of the secret value in the pipeline configuration.

### Image Restrictions

You can restrict a secret to specific Docker images, ensuring it's only used in expected contexts:

```yaml
# In the UI/CLI, set images to: target/vela-kaniko
# The secret will only be injected into steps using that image
```

## Log Masking

Vela automatically masks secret values in step/service logs. If a log line exactly matches a secret value, it's replaced with `***`.

This is protection against **accidental** logging, not against determined bad actors. Combine masking with the other security settings for defense in depth.

## Examples

### Example: Multi-Scope Pipeline

```yaml
version: "1"

secrets:
  - name: docker_password
    key: myorg/myrepo/docker_password
    engine: native
    type: repo

  - name: npm_token
    key: myorg/npm_token
    engine: native
    type: org

  - name: deploy_key
    key: myorg/platform-team/deploy_key
    engine: native
    type: shared

steps:
  - name: install
    image: node:22-alpine
    secrets: [npm_token]
    commands:
      - npm ci

  - name: publish image
    image: target/vela-kaniko:latest
    secrets: [docker_password]
    ruleset:
      event: push
      branch: main
    parameters:
      registry: index.docker.io
      repo: index.docker.io/myorg/myapp

  - name: deploy
    image: myorg/deployer:latest
    secrets: [deploy_key]
    ruleset:
      event: deployment
    commands:
      - ./deploy.sh
```

### Example: Secret with Source/Target

```yaml
secrets:
  - name: github_token
    key: myorg/myrepo/github_token
    engine: native
    type: repo

steps:
  - name: custom plugin
    image: myorg/my-plugin:latest
    secrets:
      - source: github_token
        target: PARAMETER_API_TOKEN
    parameters:
      endpoint: https://api.example.com
```

## Pitfalls

- A secret declaration requires all four fields: `name`, `key`, `engine`, and `type`. The Vela compiler needs the full set to know where to look up the secret and how to inject it. Legacy shorthand that omitted some fields no longer works -- incomplete declarations cause compile or runtime errors with messages about invalid secret paths.
- Secrets do not have the `pull_request` event enabled by default, and this is a deliberate security choice. PR builds can be triggered by external contributors who do not have write access to the repository, which means enabling secrets on PRs could expose sensitive values to untrusted code. If you need secrets in PR builds, explicitly enable the `pull_request` event on the secret and consider adopting a build approval policy to gate execution.
- Referencing a secret with `${SECRET_NAME}` substitution causes the Vela server to resolve the secret value at compile time and embed it directly into the pipeline YAML. This means the plaintext value appears in the compiled pipeline configuration. The `source`/`target` mapping avoids this by injecting the secret at runtime directly into the container environment, keeping it out of the compiled pipeline.
- Each secret type has a distinct key pattern that reflects its access scope: repo secrets use `<org>/<repo>/<name>`, org secrets use `<org>/<name>`, and shared secrets use `<org>/<team>/<name>`. A mismatch between the `type` field and the key format results in a lookup failure because Vela parses the key path based on the declared type.
- Shared secrets have `allow_command` set to `false` by default, which means they are not injected into steps that have a `commands` block or custom `entrypoint`. This is a security measure to limit shared secrets to plugin-only usage. If you need a shared secret in a step that runs commands, you must explicitly update the secret settings to allow commands.
- Log masking works by scanning log output for exact matches of secret values and replacing them with `***`. It does not catch substrings, base64-encoded forms, values split across multiple lines, or other transformations. Treat masking as protection against accidental leaks, not as a security boundary -- combine it with image restrictions and command restrictions for defense in depth.

## Quick Reference

```yaml
# Secret declaration
secrets:
  - name: my_secret           # referenced in steps
    key: org/repo/my_secret   # repo type key pattern
    engine: native             # storage backend
    type: repo                 # repo | org | shared
    pull: build_start          # build_start | step_start

# Key patterns by type
# repo:   <org>/<repo>/<name>
# org:    <org>/<name>
# shared: <org>/<team>/<name>

# Step injection (simple)
secrets: [my_secret]           # -> $MY_SECRET env var

# Step injection (remapped)
secrets:
  - source: my_secret
    target: CUSTOM_VAR_NAME    # -> $CUSTOM_VAR_NAME env var

# CLI management (see the vela-cli skill for full CLI usage)
# vela add secret --secret.engine native --secret.type repo --name foo --value bar
# vela get secrets --secret.engine native --secret.type repo
# vela view secret --secret.engine native --secret.type repo --name foo
```
