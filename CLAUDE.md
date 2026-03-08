# CLAUDE.md

This is the vela-skills repository -- a research workspace and skill library for [Vela](https://go-vela.github.io/docs/), Target's CI/CD pipeline automation framework.

## Repository structure

- `.agents/skills/` -- 12 Agent Skills covering the full Vela surface area (pipeline authoring, secrets, rulesets, stages, plugins, etc.)
- `install.sh` -- Installer for distributing skills to user-level agent directories

## Neighbor repositories

This repo lives inside a `vela-workshop/` directory alongside sibling clones of go-vela repos. These siblings are read-only references -- do not modify them.

| Sibling directory | What it contains |
|---|---|
| `../docs/` | Official Vela documentation site (Markdown source) |
| `../server/` | Vela server -- API, compiler, database, webhook processing |
| `../worker/` | Vela worker -- build executor, step/service runner |
| `../ui/` | Vela web UI (Elm) |
| `../vela-tutorials/` | Tutorial pipelines and examples |

When researching Vela behavior, check the sibling `docs/` repo first for user-facing documentation, then `server/` or `worker/` for implementation details.

## Working with skills

The skills in `.agents/skills/` follow the [Agent Skills specification](https://agentskills.io/specification). Each skill is a directory containing a `SKILL.md` with YAML frontmatter and markdown instructions.

When editing skills:
- Keep `SKILL.md` files under 500 lines
- Use imperative voice in instructions
- Explain the "why" behind recommendations, not just the "what"
- Cross-reference related skills (e.g., "See the vela-rulesets skill for details")
- Add concrete YAML examples that are copy-paste ready

See `README.md` for the full skill inventory and installation instructions.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/). Format: `<type>: <description>`

Common types:
- `feat:` -- new skill or feature
- `fix:` -- bug fix or correction
- `docs:` -- documentation changes (README, CLAUDE.md)
- `refactor:` -- restructuring without behavior change
- `chore:` -- maintenance (install script, gitignore, CI)
