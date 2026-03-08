# Vela Agent Skills

12 [Agent Skills](https://agentskills.io) that give AI coding agents deep expertise on [Vela](https://go-vela.github.io/docs/) CI/CD. Each skill follows the [Agent Skills specification](https://agentskills.io/specification) and works with Claude Code, OpenAI Codex, GitHub Copilot, and other compatible tools.

## Skills

| Skill | What it covers |
|-------|---------------|
| `vela-pipeline-authoring` | Writing `.vela.yml` from scratch -- steps vs stages, keys, metadata |
| `vela-environment` | Environment variables, `${VAR}` substitution, `VELA_OUTPUTS` |
| `vela-rulesets` | Conditional execution -- compile-time vs runtime rules, event scoping |
| `vela-secrets` | Secret scopes (repo/org/shared), injection, security defaults |
| `vela-cli` | Pipeline validation, repo management, secret CRUD, deployments |
| `vela-plugins` | Plugin configuration, `PARAMETER_*` env vars, official plugins |
| `vela-stages` | Parallel execution, `needs:` dependencies, compile-time pruning |
| `vela-templates` | Why to avoid templates; reference docs if you must use them |
| `vela-services` | Service containers for integration testing, readiness checks |
| `vela-deployments` | Deployment targets, parameters, CLI triggers |
| `vela-troubleshooting` | Diagnosing build failures -- webhooks, secrets, YAML parsing |
| `vela-images` | Docker image selection -- alpine variants, version pinning |

## Install

> [!NOTE]
> The install script requires bash and is designed for macOS and Linux. Windows users should install via [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or manually copy the skill directories from `.agents/skills/` to your agent's user-level skills folder.

### Quick install (user-level)

Install skills to your user-level directory so they're available across all projects.

From a local clone:

```sh
git clone https://github.com/ryanmr/vela-skills.git
cd vela-skills
./install.sh
```

Or as a one-liner:

```sh
curl -fsSL https://raw.githubusercontent.com/ryanmr/vela-skills/main/install.sh | bash
```

### What the installer does

The script detects which AI tools you have installed and copies all 12 skills to each tool's user-level skills directory:

| Tool | Detected by | Installs to |
|------|-------------|-------------|
| **Cross-client** | Always | `~/.agents/skills/vela-*/` |
| **Claude Code** | `claude` CLI or `~/.claude/` | `~/.claude/skills/vela-*/` |
| **OpenAI Codex** | `codex` CLI or `~/.codex/` | `~/.codex/skills/vela-*/` |
| **GitHub Copilot** | `copilot` CLI, `gh copilot`, or `~/.copilot/` | `~/.copilot/skills/vela-*/` |

The script is idempotent -- re-running it skips skills that are already up to date.

```sh
./install.sh --list        # Preview what will be installed
./install.sh --force       # Overwrite existing skills
./install.sh --uninstall   # Remove all vela-* skills
```

### Alternative: `npx skills`

The [Vercel skills CLI](https://github.com/vercel-labs/skills) can install from this repo with auto-detection of 40+ AI tools:

```sh
npx skills add ryanmr/vela-skills -g
```

The `-g` flag installs to user-level directories. The CLI fetches directly from GitHub, so it works even in environments that restrict npm registry access.

## Project-level setup (optional)

To make these skills available at the project level in a specific repo, symlink from each tool's project-level skills directory into `.agents/skills/`.

The skills are stored in `.agents/skills/` following the [cross-client interoperability convention](https://agentskills.io/client-implementation/adding-skills-support). Each AI tool scans a different project-level path:

| Tool | Project-level path | Setup |
|------|-------------------|-------|
| **OpenAI Codex** | `.agents/skills/` | Works automatically -- no setup needed |
| **Claude Code** | `.claude/skills/` | `mkdir -p .claude && ln -s ../.agents/skills .claude/skills` |
| **GitHub Copilot** | `.github/skills/` | `mkdir -p .github && ln -s ../.agents/skills .github/skills` |

**Symlinks vs stubs**: Symlinks are simpler -- one link, zero maintenance. If symlinks don't work in your environment (Windows, CI that doesn't follow symlinks), create stub files instead. A stub is a minimal `SKILL.md` that tells the agent to read the real file:

```yaml
---
name: vela-secrets
description: See ../../.agents/skills/vela-secrets/SKILL.md
---
Read the full skill at [../../.agents/skills/vela-secrets/SKILL.md](../../.agents/skills/vela-secrets/SKILL.md).
```

## Development

See [README_WORKSPACE.md](README_WORKSPACE.md) for the research workspace layout and sibling repository setup.
