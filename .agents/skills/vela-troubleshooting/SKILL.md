---
name: vela-troubleshooting
description: "Diagnosing Vela build failures: builds that won't trigger, compile errors, YAML unmarshal issues, webhook repair, secret injection problems, pending/stuck builds, and v0.26 parser migration."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Vela build problems fall into three categories: the build **won't trigger** (no build appears), the build **won't run** (stuck or errored before execution), or the build **fails during execution**. This guide provides a decision tree for diagnosing each category.

## Decision Tree

```
Build problem?
|
+-- No build appears at all
|   -> Check webhooks (Section 1)
|
+-- Build appears but won't run / errors before execution
|   -> Check build status and error (Section 2)
|
+-- Build runs but steps fail
    -> Check step logs and configuration (Section 3)
```

## Section 1: Build Won't Trigger

The build doesn't appear in the Vela UI at all. This is a webhook delivery problem.

### Check Webhooks

View webhook deliveries to see what the server received:

- **UI**: Navigate to `https://vela.example.com/<org>/<repo>/hooks`
- **CLI**: `vela get hooks --org <org> --repo <repo>` (see the vela-cli skill for CLI setup and usage)

### Missing Webhook Signature

**Symptom**: Webhook shows "missing signature" error.

**Cause**: The webhook signature used to verify authenticity has been removed from the SCM.

**Fix**: Repair the repository to recreate the webhook:

```sh
vela repair repo --org MyOrg --repo MyRepo
```

Requires admin access on the repository.

### Payload Signature Check Failed

**Symptom**: Webhook shows "payload signature check failed" error.

**Cause**: The webhook signature has been corrupted.

**Fix**: Same as above -- repair the repository:

```sh
vela repair repo --org MyOrg --repo MyRepo
```

### Your Account Was Suspended

**Symptom**: Webhook shows "your account was suspended" error.

**Cause**: The user who originally enabled the repository had their SCM account suspended.

**Fix**: Change repository ownership to an active user:

```sh
vela chown repo --org MyOrg --repo MyRepo
```

Requires admin access.

### Event Not Enabled

**Symptom**: You push/tag/comment but no build appears.

**Cause**: The event type isn't enabled on the repository. Check repo settings.

**Fix**: Enable the event in the UI (`https://vela.example.com/<org>/<repo>/settings`) or verify with:

```sh
vela view repo --org MyOrg --repo MyRepo
```

Look for `allow_push`, `allow_pull`, `allow_tag`, `allow_deploy`, `allow_comment` settings.

## Section 2: Build Won't Run

The build appears but is stuck or errored.

### Build Is Pending

**Symptom**: Build stays in `pending` status.

**Cause**: No workers are available to pick up the build. All workers are busy with other builds.

**Fix**: Wait for a worker to become available. If this persists, check with your Vela platform administrators about worker capacity.

### Repo Exceeded Build Limit

**Symptom**: Webhook shows "repo exceeded build limit" error.

**Cause**: Too many concurrent `pending` or `running` builds for this repo.

**Fix**: Cancel a pending/running build or increase the build limit:

```sh
# Cancel a build
vela cancel build --org MyOrg --repo MyRepo --build 42

# Or increase the limit
vela update repo --org MyOrg --repo MyRepo --build.limit 15
```

### Queue Length Exceeded

**Symptom**: Error "queue length exceeds configured limit" when restarting a pending build.

**Cause**: The global queue is too large. Platform admins have set a queue size limit.

**Fix**: Wait for the queue to drain. Don't retry -- it will just add more to the queue.

### Unable To Unmarshal YAML

**Symptom**: Build errors with "unable to unmarshal" before any steps run.

**Cause**: Invalid YAML syntax in your pipeline.

**Fix**: Validate locally:

```sh
vela validate pipeline
```

Common YAML issues:
- Duplicate keys in a map
- Incorrect indentation
- Missing quotes around special characters
- Invalid YAML merge key (`<<`) usage (see YAML Anchor Issues below)

You can also validate your pipeline against the official JSON Schema at https://github.com/go-vela/server/releases/latest/download/schema.json.

### Invalid Secret Path

**Symptom**: Build errors with "invalid secret path".

**Cause**: The `key` field in a secret declaration doesn't match the expected pattern for its type.

**Fix**: Ensure the key follows the correct pattern:

```yaml
secrets:
  # Repo: <org>/<repo>/<name>
  - name: foo
    key: myorg/myrepo/foo
    engine: native
    type: repo

  # Org: <org>/<name>
  - name: bar
    key: myorg/bar
    engine: native
    type: org

  # Shared: <org>/<team>/<name>
  - name: baz
    key: myorg/myteam/baz
    engine: native
    type: shared
```

Legacy shorthand (`- name: foo` without `key`, `engine`, `type`) no longer works.

### Invalid Reference Format

**Symptom**: Step fails with "invalid reference format".

**Cause**: The `image` value for a step is not a valid Docker image reference.

**Fix**: Verify the image exists:

```sh
docker pull <image>
```

Check for typos, missing registry prefixes, or invalid tag formats.

### Repo Is Not Trusted

**Symptom**: Build errors with "repo is not trusted".

**Cause**: Platform administrators have restricted privileged image execution. Your repo isn't in the allowlist.

**Fix**: Contact your Vela platform administrators or avoid using privileged images.

## Section 3: Build Fails During Execution

### Context Deadline Exceeded

**Symptom**: Build fails with "context deadline exceeded" after running for a long time.

**Cause**: The build exceeded the repository's timeout setting (default: 30 minutes).

**Fix**:
1. Optimize your pipeline (use rulesets to skip unnecessary steps, use stages for parallel execution)
2. Increase the timeout:

```sh
vela update repo --org MyOrg --repo MyRepo --timeout 60
```

### Secrets Not Available

**Symptom**: Secret environment variables are empty in steps.

**Causes and fixes** (see the vela-secrets skill for full secret configuration details):

| Cause | Fix |
|-------|-----|
| Secret not declared in `secrets:` block | Add full declaration with `name`, `key`, `engine`, `type` |
| Wrong `key` pattern for type | Follow `<org>/<repo>/<name>` (repo), `<org>/<name>` (org), `<org>/<team>/<name>` (shared) |
| PR event and secret doesn't allow `pull_request` | Enable `pull_request` event on the secret |
| `allow_command: false` and step has `commands:` | Use plugin mode (parameters) or enable commands on the secret |
| Image restriction on secret | Verify the step image matches the secret's allowed images |
| `allow_substitution: false` and using `${SECRET}` | Use source/target mapping instead |

### Steps Skipped Unexpectedly

**Symptom**: Steps don't run even though you expected them to.

**Causes**:
- Compile-time ruleset didn't match (check `event`, `branch`, `path`, `tag`, `target`)
- Stage was pruned because all its steps had non-matching compile-time rules
- `needs:` dependency was pruned, causing unexpected execution order

**Debug**: Use `vela validate pipeline` with context flags to see what the compiled pipeline looks like:

```sh
vela validate pipeline --event push --branch main
vela validate pipeline --event pull_request --branch feature-1
```

## YAML Anchor Issues (v0.26+)

Since v0.26, Vela uses the standard `go-yaml` parser which is stricter about YAML. See the vela-pipeline-authoring skill for YAML anchor best practices.

### Duplicate Merge Keys

**Wrong:**
```yaml
steps:
  - name: example
    environment:
      REPO: ${VELA_REPO_FULL_NAME}
      <<: *base_env
      <<: *release_env      # duplicate << key -- error!
```

**Fix:** Use a sequence:
```yaml
steps:
  - name: example
    environment:
      REPO: ${VELA_REPO_FULL_NAME}
      <<:
        - *base_env
        - *release_env
```

### Anchor Parameter Collision

**Wrong:**
```yaml
plugin_base: &plugin_base
  image: my-plugin:latest
  parameters:
    log_level: debug

steps:
  - name: my-step
    <<: *plugin_base
    parameters:              # this REPLACES the anchor's parameters
      region: us-west
```

**Fix:** Separate the base parameters into their own anchor:
```yaml
plugin_base: &plugin_base
  image: my-plugin:latest

plugin_params: &plugin_params
  log_level: debug

steps:
  - name: my-step
    <<: *plugin_base
    parameters:
      <<: *plugin_params
      region: us-west
```

## Pitfalls

- When a build doesn't appear, the instinct is to look at your pipeline YAML -- but if there's no build record at all, Vela never received the event. The webhook delivery log (visible in the UI or via `vela get hooks`) tells you whether the event reached Vela and what error it returned. Starting there saves you from debugging a pipeline that was never even compiled.
- A missing build and a failed build are fundamentally different problems with different root causes. A missing build means the webhook didn't arrive or was rejected (signature issues, suspended account, event not enabled). A failed build means Vela received the event but something went wrong during compilation or execution. Treating them the same leads you down the wrong diagnostic path.
- When the queue is full, restarting a stuck build adds another entry to the queue, making the backlog worse and pushing everyone's builds further out. The queue has a finite capacity set by platform admins, and hitting that limit means you need to wait for existing builds to drain, not pile on more.
- YAML syntax errors, invalid secret paths, and ruleset typos are all caught by `vela validate pipeline` locally in seconds. Pushing to discover these errors means waiting for a webhook round-trip, a compile attempt, and then reading the error from the UI -- a feedback loop that's minutes instead of seconds.
- Older Vela pipelines could declare secrets with just `- name: foo` and let the system infer the rest. That shorthand no longer works -- the compiler needs explicit `key`, `engine`, and `type` fields to know where to look up the secret. Without them, you get an "invalid secret path" error that can be confusing if you're following outdated examples.

## Quick Reference

```sh
# Diagnose webhook issues
vela get hooks --org <org> --repo <repo>

# Repair webhook
vela repair repo --org <org> --repo <repo>

# Change repo ownership
vela chown repo --org <org> --repo <repo>

# Validate pipeline locally
vela validate pipeline
vela validate pipeline --event push --branch main

# Check/update repo settings
vela view repo --org <org> --repo <repo>
vela update repo --org <org> --repo <repo> --build.limit 15
vela update repo --org <org> --repo <repo> --timeout 60

# Cancel stuck build
vela cancel build --org <org> --repo <repo> --build <n>

# View build details
vela view build --org <org> --repo <repo> --build <n>
vela get logs --org <org> --repo <repo> --build <n>
```
