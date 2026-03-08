---
name: vela-plugins
description: "Plugin configuration in Vela: the parameters key, PARAMETER_* env vars, official plugins (Docker, Kaniko, Slack, Downstream), secret injection into plugins, and building custom plugins."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Configure plugins in Vela steps using the `parameters:` key, which maps each key to a `PARAMETER_<KEY_NAME>` environment variable inside the container. Plugins are Docker containers that read these variables and perform specific tasks.

There are two types of plugins:
- **Pipeline plugins** -- used in steps to build images, send notifications, deploy code, etc.
- **Secret plugins** -- used in the `secrets:` block to fetch secrets from external providers

## How Plugins Work

A plugin is just a Docker image that reads `PARAMETER_*` environment variables. When you write:

```yaml
steps:
  - name: publish
    image: target/vela-kaniko:latest
    pull: always
    parameters:
      registry: index.docker.io
      repo: index.docker.io/myorg/myapp
```

Vela injects these environment variables into the container:
- `PARAMETER_REGISTRY=index.docker.io`
- `PARAMETER_REPO=index.docker.io/myorg/myapp`

The plugin's entrypoint reads these variables and acts accordingly.

## Official Plugins

Vela maintains a set of official plugins. Key plugins include:

| Plugin               | Image                            | Purpose                        |
|----------------------|----------------------------------|--------------------------------|
| Docker/Kaniko        | `target/vela-kaniko`             | Build and push Docker images   |
| Git                  | `target/vela-git`                | Git operations                 |
| Slack                | `target/vela-slack`              | Send Slack notifications       |
| Downstream           | `target/vela-downstream`         | Trigger builds in other repos  |
| Artifactory          | `target/vela-artifactory`        | Publish to Artifactory         |
| S3 Cache             | `target/vela-s3-cache`           | Cache build artifacts in S3    |
| NPM                  | `target/vela-npm`                | Publish NPM packages           |
| GitHub Release       | `target/vela-github-release`     | Create GitHub releases         |
| Kubernetes           | `target/vela-kubernetes`         | Kubernetes deployments         |
| Terraform            | `target/vela-terraform`          | Terraform operations           |
| Hugo                 | `target/vela-hugo`               | Build Hugo sites               |
| Email                | `target/vela-email`              | Send email notifications       |
| Ansible              | `target/vela-ansible`            | Run Ansible playbooks          |
| K6                   | `target/vela-k6`                 | Run K6 load tests              |
| SSH/SCP              | `target/vela-openssh`            | SSH and SCP operations         |
| InfluxDB             | `target/vela-influx`             | Write metrics to InfluxDB      |
| Manifest Tool        | `target/vela-manifest-tool`      | Docker manifest operations     |
| Build Summary        | `target/vela-build-summary`      | Build summary notifications    |
| AWS Credentials      | `cargill/vela-aws-credentials`   | AWS credential injection       |

## Configuring Plugins

### Parameters

The `parameters:` key accepts any key-value structure. Values can be strings, lists, maps, or booleans:

```yaml
steps:
  - name: docker
    image: target/vela-kaniko:latest
    pull: always
    parameters:
      registry: index.docker.io
      repo: index.docker.io/myorg/myapp
      tags:
        - latest
        - ${VELA_BUILD_COMMIT:0:8}
      build_args:
        - "VERSION=${VELA_BUILD_COMMIT:0:8}"
      dry_run: false
```

### Secrets with Plugins

Plugins often need secrets (registry passwords, API tokens). Inject them via the `secrets:` key on the step. See the vela-secrets skill for full secret configuration details:

```yaml
secrets:
  - name: docker_password
    key: myorg/myrepo/docker_password
    engine: native
    type: repo

steps:
  - name: docker
    image: target/vela-kaniko:latest
    pull: always
    secrets: [docker_password]
    parameters:
      registry: index.docker.io
      repo: index.docker.io/myorg/myapp
```

The secret `docker_password` is injected as `DOCKER_PASSWORD`. Many plugins look for secrets under conventional names.

For plugins that expect secrets under a specific variable name, use source/target mapping:

```yaml
steps:
  - name: custom plugin
    image: myorg/my-plugin:latest
    secrets:
      - source: github_token
        target: PARAMETER_API_TOKEN
```

## Building Custom Plugins

A custom plugin is any Docker image that reads `PARAMETER_*` environment variables. You can write one in any language.

### Bash Plugin

The simplest approach -- a shell script in a Docker image:

```dockerfile
FROM alpine:3
COPY --chmod=0755 script.sh /bin/script.sh
ENTRYPOINT ["/bin/script.sh"]
```

```bash
#!/bin/sh
# script.sh
echo "Registry: ${PARAMETER_REGISTRY}"
echo "Repo: ${PARAMETER_REPO}"
# do work...
```

Use in a pipeline:

```yaml
steps:
  - name: my-plugin
    image: myorg/my-plugin:latest
    parameters:
      registry: docker.io
      repo: myorg/myapp
```

### Conventions

- Read configuration from `PARAMETER_*` environment variables
- Read secrets from uppercase environment variable names matching the secret name
- Exit `0` on success, non-zero on failure
- Write useful output to stdout/stderr for build logs

## Using `commands` vs `parameters`

A step can use `commands` (shell script) or `parameters` (plugin mode), but they serve different purposes:

- **`commands`**: Vela wraps your commands in a shell script and executes them. The image is treated as a general-purpose container.
- **`parameters`**: Vela sets `PARAMETER_*` env vars and runs the image's default entrypoint. The image is treated as a plugin.

You can combine `commands` with a step that has secrets, but if a secret has `allow_command: false`, it won't be injected.

## Examples

### Example: Build and Push Docker Image

```yaml
version: "1"

secrets:
  - name: docker_password
    key: myorg/myrepo/docker_password
    engine: native
    type: repo

steps:
  - name: publish
    image: target/vela-kaniko:latest
    pull: always
    secrets: [docker_password]
    ruleset:
      event: push
      branch: main
    parameters:
      registry: index.docker.io
      repo: index.docker.io/myorg/myapp
      tags:
        - latest
        - ${VELA_BUILD_COMMIT:0:8}
```

### Example: Slack Notification on Failure

```yaml
steps:
  - name: notify
    image: target/vela-slack:latest
    pull: always
    secrets: [slack_webhook]
    ruleset:
      status: failure
      continue: true
    parameters:
      text: "Build #${VELA_BUILD_NUMBER} failed for ${VELA_REPO_FULL_NAME}"
```

### Example: Trigger Downstream Build

```yaml
steps:
  - name: trigger deploy repo
    image: target/vela-downstream:latest
    pull: always
    secrets: [vela_token]
    ruleset:
      event: push
      branch: main
    parameters:
      server: https://vela.example.com
      repos:
        - myorg/deploy-repo
      branch: main
```

## Pitfalls

- Plugin images get frequent updates, but Docker's default pull policy (`not_present`) only pulls if the image is not already cached on the worker. This means different workers may run different versions of the same plugin depending on what is cached locally. Using `pull: always` ensures every build gets the same version regardless of which worker picks it up. See the vela-images skill for more on pull policies and image selection.
- The `parameters:` block is written directly into the pipeline YAML, which typically lives in version control. Any secret value placed there is committed in plaintext for anyone with repo access to read. The `secrets:` key exists specifically to inject sensitive values as environment variables at runtime without exposing them in the source file.
- When a step uses `commands`, Vela overrides the container's entrypoint with a shell wrapper that executes your script. When a step uses `parameters`, Vela leaves the entrypoint alone and passes configuration via `PARAMETER_*` environment variables. Using both on the same step creates a conflict: the shell wrapper replaces the plugin entrypoint, so the plugin logic never runs and the parameters go unused.
- Each plugin reads secrets from specific environment variable names (for example, `DOCKER_PASSWORD` or `SLACK_WEBHOOK`). If the secret you inject does not match the variable name the plugin expects, the plugin simply will not see it. Check the plugin's documentation for the exact names, or use `source`/`target` mapping to bridge any naming mismatch.
- Vela serializes parameter values into environment variables, but how the plugin parses them depends on its implementation. A plugin expecting a boolean `true` may break if it receives the string `"true"`, and list parameters get serialized in a specific format the plugin must understand. Consulting the plugin docs for expected types prevents subtle runtime failures.

## Quick Reference

```yaml
# Plugin step pattern
steps:
  - name: my-plugin
    image: target/vela-<plugin>:latest
    pull: always
    secrets: [secret_name]
    ruleset:
      event: push
      branch: main
    parameters:
      key: value
      list_key:
        - item1
        - item2

# Parameters become: PARAMETER_KEY, PARAMETER_LIST_KEY
# Secrets become: SECRET_NAME (uppercase)

# Official plugin image prefix: target/vela-*
# Secret plugin image prefix: target/secret-*
```
