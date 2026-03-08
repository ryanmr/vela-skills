---
name: vela-templates
description: "Vela templates (Go templates, Starlark, render_inline) for reusable pipeline fragments. Recommends against templates in favor of explicit repetition; reference docs if you must use them."
metadata:
  author: ryanmr
  version: "1.0"
---

## Overview

Avoid Vela templates. Prefer explicit, repeated pipeline YAML instead. Templates introduce significant complexity, lock-in, and debugging difficulty that rarely justifies the reuse benefit. See the vela-pipeline-authoring skill for guidance on writing clear, maintainable pipelines without templates.

If you must use templates, this skill documents the syntax and pitfalls.

## Why You Should Avoid Templates

Templates sound appealing in theory but create real problems in practice:

- **High complexity**: Go template syntax (`{{ if }}`, `{{ range }}`, sprig functions) is hard to read, hard to write, and hard to review. Starlark adds a whole programming language on top of YAML.
- **Difficult debugging**: When a template-expanded pipeline fails, you're debugging the *compiled output*, not the source. Error messages reference generated YAML, not your template logic.
- **Lock-in**: Once your organization adopts templates, every pipeline depends on them. Changing a shared template can break dozens of repos simultaneously. Versioning helps but adds more complexity.
- **Hidden behavior**: Reviewers can't see the full pipeline in a PR -- they see a template reference. This makes code review harder and reduces transparency.
- **Compile-time failures**: Template expansion errors (missing variables, type mismatches) surface as confusing compile errors, not clear validation messages.
- **Validation burden**: Testing templates locally requires `vela validate pipeline --template` with GitHub tokens or local file overrides (see the vela-cli skill for details). This is significantly more friction than validating plain YAML.

### What To Do Instead

**Prefer explicit repetition.** Modern multi-cursor editors and AI coding agents can easily manage repeated YAML blocks across repositories. Copy-pasting a 10-line step definition into multiple repos is:

- Transparent: anyone can read the full pipeline
- Independent: changing one repo's pipeline doesn't break others
- Debuggable: errors map directly to the YAML you wrote
- Reviewable: PR diffs show exactly what changed

If you have 50+ repositories that genuinely need identical pipeline logic, consider a code generation approach that produces plain `.vela.yml` files rather than runtime templates. See the vela-pipeline-authoring skill for pipeline structure guidance.

## If You Must Use Templates

For teams that have already adopted templates or have a compelling reason, here is the reference documentation.

### Template Declaration

Templates are declared at the top level and referenced in steps:

```yaml
version: "1"

templates:
  - name: go-build
    source: github.com/myorg/vela-templates/go-build.yml
    type: github
    format: go

steps:
  - name: build
    template:
      name: go-build
      vars:
        image: golang:1.23-alpine
```

### Template Keys

| Key      | Required | Type   | Description                                    |
|----------|----------|--------|------------------------------------------------|
| `name`   | Y        | string | Unique identifier, referenced in steps         |
| `source` | Y        | string | Path to template file                          |
| `type`   | Y        | string | `github` or `file` (local)                     |
| `format` | N        | string | `go` (default), `golang`, or `starlark`        |

### Source Versioning

Pin templates to a branch, tag, or commit with `@`:

```yaml
templates:
  - name: go-build
    source: github.com/myorg/vela-templates/go-build.yml@v2.1.0
    type: github
```

Without `@`, the default branch is used (not recommended -- this creates implicit coupling to whatever's on `main`).

### Local File Templates

Reference a template within the same repository:

```yaml
templates:
  - name: local-template
    source: .vela/templates/build.yml
    type: file
```

### Template File Structure

A template file must set `metadata.template: true`:

```yaml
metadata:
  template: true

steps:
  - name: build
    image: {{ .image }}
    commands:
      - go build ./...
```

### Go Template Syntax

Templates use Go's `text/template` package extended with [sprig](http://masterminds.github.io/sprig/) functions:

```yaml
metadata:
  template: true

steps:
  - name: build
    image: {{ .image }}
    pull: always
    commands:
      - go test ./...
      - go build
```

Variables are passed via `vars:` in the calling pipeline and accessed with `{{ .varname }}`.

### Starlark Templates

Starlark templates are Python-like scripts that return a pipeline dictionary:

```python
def main(ctx):
    return {
        'version': '1',
        'steps': [
            {
                'name': 'build',
                'image': ctx["vars"]["image"],
                'commands': ['go build', 'go test'],
            },
        ],
    }
```

### Render Inline

`render_inline: true` in metadata allows templates to inject stages/steps/services/secrets without explicit step references:

```yaml
version: "1"
metadata:
  render_inline: true

templates:
  - name: go
    source: github.com/myorg/templates/go.yml
    type: github
    format: go
    vars:
      image: golang:1.23-alpine
```

### Rulesets for Template Calls

Steps that call templates can have compile-time rulesets:

```yaml
steps:
  - name: pr-flow
    ruleset:
      event: pull_request
    template:
      name: pr_flow
```

Only compile-time rules work here. Runtime rules (`status`) do not apply since the template is merged before execution.

### Nested Templates

Templates can call other templates (since v0.20.0). Depth is limited by `VELA_MAX_TEMPLATE_DEPTH` (default: 3).

### Validating Templates

```sh
# Validate with template expansion (requires GitHub token for remote templates)
vela validate pipeline --template --compiler.github.token <token>

# Use a local file instead of fetching from remote
vela validate pipeline --template --template-file name:path/to/file
```

## Pitfalls

- Templates pay off only when many repositories share truly identical logic. Below roughly 20 consumers, the cost of maintaining template code (Go template syntax, versioning, cross-repo testing) exceeds the cost of simply copying a few YAML blocks. Modern editors and AI tools make managing repeated YAML across repos trivially easy, while debugging a broken template requires understanding the expansion pipeline.
- Without an `@tag` or `@commit` pin in the source URL, Vela fetches the template from the default branch at compile time. This means any push to that branch silently changes the behavior of every consuming pipeline. Pinning to a version gives consumers an explicit upgrade path and prevents a single template change from breaking dozens of repos at once.
- Vela pipelines can use either `stages` or `steps` at the top level, but not both. When a `render_inline` template expands, its output is merged into the calling pipeline. If the template produces stages but the caller already defines steps (or vice versa), compilation fails. Both the template and caller must agree on which structure they use.
- The `metadata.template: true` marker tells the Vela compiler to treat the file as a template rather than a standalone pipeline. Without it, the compiler attempts to interpret Go template directives like `{{ .image }}` as literal YAML content, which produces parse errors or silently wrong output.
- Go templates fail open on missing variables -- `{{ .image }}` with no `image` in `vars` produces an empty string or a cryptic nil-pointer error depending on context. Because the error surfaces during compilation rather than in your template source, the message rarely points you to the actual missing variable. Defining sensible defaults with `{{ default "golang:1.23" .image }}` or documenting required vars helps prevent this.
- Each level of template nesting multiplies the debugging difficulty because you must mentally trace expansion through multiple files to understand the final compiled pipeline. Error messages reference the final output, not intermediate template layers, so a bug in a deeply nested template can be very hard to locate. Keeping nesting to one level preserves most of the reuse benefit while staying debuggable.

## Quick Reference

```yaml
# Caller pipeline
templates:
  - name: my-template
    source: github.com/org/repo/template.yml@v1.0.0
    type: github          # github | file
    format: go            # go | starlark (default: go)

steps:
  - name: from-template
    template:
      name: my-template
      vars:
        image: golang:1.23-alpine

# Template file
metadata:
  template: true
steps:
  - name: build
    image: {{ .image }}
    commands:
      - go build ./...

# Validation
# vela validate pipeline --template --template-file name:path
```
