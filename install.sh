#!/usr/bin/env bash
set -euo pipefail

# Vela Agent Skills Installer
# Installs Vela CI/CD skills to your AI coding agent's user-level skills directory.
# Supports Claude Code, OpenAI Codex, and the cross-client .agents/ convention.
#
# Usage:
#   ./install.sh                    # Install from local clone
#   curl -fsSL <raw-url> | bash     # Install from GitHub (fetches skills via git)
#
# Options:
#   --uninstall   Remove all vela-* skills from detected agent directories
#   --list        Show where skills would be installed without making changes
#   --force       Overwrite existing skills without prompting

REPO_URL="https://github.com/ryanmr/vela-skills.git"
SKILL_PREFIX="vela-"

# --- Helpers ---

log()  { printf '  %s\n' "$*"; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; }

# --- Agent detection ---
# Builds two parallel arrays: AGENT_NAMES and AGENT_DIRS
# Compatible with bash 3.x (no associative arrays).
#
# Detection uses CLI binary first (command -v), then falls back to
# config directory existence. This catches tools that are installed
# but not yet run (no config dir) and tools that were uninstalled
# but left config behind.

AGENT_NAMES=()
AGENT_DIRS=()

has_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_agents() {
  local home="$HOME"

  # Cross-client convention -- always install here
  AGENT_NAMES+=("agents")
  AGENT_DIRS+=("$home/.agents/skills")

  # Claude Code: `claude` CLI or ~/.claude/ config
  if has_cmd claude || [[ -d "$home/.claude" ]]; then
    AGENT_NAMES+=("claude-code")
    AGENT_DIRS+=("$home/.claude/skills")
  fi

  # OpenAI Codex: `codex` CLI or ~/.codex/ config
  if has_cmd codex || [[ -d "$home/.codex" ]]; then
    AGENT_NAMES+=("codex")
    AGENT_DIRS+=("$home/.codex/skills")
  fi

  # GitHub Copilot: `copilot` CLI, `gh copilot` extension, or ~/.config/github-copilot/
  if has_cmd copilot || gh copilot --version >/dev/null 2>&1 || [[ -d "$home/.config/github-copilot" ]]; then
    AGENT_NAMES+=("github-copilot")
    AGENT_DIRS+=("$home/.config/github-copilot/skills")
  fi
}

# --- Source resolution ---
# If run from a local clone, use the local .agents/skills/.
# If run via curl|bash, clone to a temp directory first.

SOURCE_DIR=""
CLEANUP_DIR=""

resolve_source() {
  local script_dir
  # Handle both ./install.sh and curl|bash invocations
  if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" != "bash" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  else
    script_dir=""
  fi

  if [[ -n "$script_dir" ]] && [[ -d "$script_dir/.agents/skills" ]]; then
    SOURCE_DIR="$script_dir/.agents/skills"
  else
    info "Fetching skills from $REPO_URL..."
    CLEANUP_DIR="$(mktemp -d)"
    git clone --depth 1 --filter=blob:none --sparse "$REPO_URL" "$CLEANUP_DIR" 2>/dev/null
    (cd "$CLEANUP_DIR" && git sparse-checkout set .agents/skills) 2>/dev/null
    SOURCE_DIR="$CLEANUP_DIR/.agents/skills"

    if [[ ! -d "$SOURCE_DIR" ]]; then
      err "Failed to fetch skills from repository"
      rm -rf "$CLEANUP_DIR"
      exit 1
    fi
  fi
}

cleanup_source() {
  if [[ -n "$CLEANUP_DIR" ]]; then
    rm -rf "$CLEANUP_DIR"
  fi
}

# --- Actions ---

do_list() {
  detect_agents

  info "Detected agent directories:"
  local i
  for ((i = 0; i < ${#AGENT_NAMES[@]}; i++)); do
    local name="${AGENT_NAMES[$i]}"
    local path="${AGENT_DIRS[$i]}"
    if [[ -d "$path" ]]; then
      log "$name: $path (exists)"
    else
      log "$name: $path (will create)"
    fi
  done

  echo
  info "Skills to install:"
  resolve_source
  for skill_dir in "$SOURCE_DIR"/${SKILL_PREFIX}*/; do
    [[ -d "$skill_dir" ]] || continue
    log "$(basename "$skill_dir")"
  done
  cleanup_source
}

do_install() {
  local force="${1:-false}"

  detect_agents
  resolve_source
  trap cleanup_source EXIT

  # Count skills
  local skill_count=0
  for skill_dir in "$SOURCE_DIR"/${SKILL_PREFIX}*/; do
    [[ -d "$skill_dir" ]] && ((skill_count++)) || true
  done

  if [[ $skill_count -eq 0 ]]; then
    err "No skills found in source directory"
    exit 1
  fi

  info "Installing $skill_count Vela skills..."
  echo

  local installed=0
  local i
  for ((i = 0; i < ${#AGENT_NAMES[@]}; i++)); do
    local agent="${AGENT_NAMES[$i]}"
    local target_base="${AGENT_DIRS[$i]}"
    mkdir -p "$target_base"

    for skill_dir in "$SOURCE_DIR"/${SKILL_PREFIX}*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name="$(basename "$skill_dir")"
      local target="$target_base/$skill_name"

      if [[ -d "$target" ]] && [[ "$force" != "true" ]]; then
        if diff -rq "$skill_dir" "$target" >/dev/null 2>&1; then
          continue
        else
          log "Updating $skill_name -> $target_base/"
        fi
      fi

      rm -rf "$target"
      cp -R "$skill_dir" "$target"
      ((installed++)) || true
    done

    ok "$agent: $target_base/"
  done

  echo
  if [[ $installed -eq 0 ]]; then
    ok "All skills already up to date"
  else
    ok "Installed $installed skill(s) across ${#AGENT_NAMES[@]} agent location(s)"
  fi
}

do_uninstall() {
  detect_agents

  info "Removing Vela skills..."
  local removed=0

  local i
  for ((i = 0; i < ${#AGENT_NAMES[@]}; i++)); do
    local target_base="${AGENT_DIRS[$i]}"
    for skill_dir in "$target_base"/${SKILL_PREFIX}*/; do
      [[ -d "$skill_dir" ]] || continue
      rm -rf "$skill_dir"
      log "Removed $(basename "$skill_dir") from $target_base/"
      ((removed++)) || true
    done
  done

  if [[ $removed -eq 0 ]]; then
    ok "No Vela skills found to remove"
  else
    ok "Removed $removed skill(s)"
  fi
}

# --- Main ---

main() {
  local action="install"
  local force="false"

  for arg in "$@"; do
    case "$arg" in
      --uninstall) action="uninstall" ;;
      --list)      action="list" ;;
      --force)     force="true" ;;
      --help|-h)
        echo "Vela Agent Skills Installer"
        echo
        echo "Usage: ./install.sh [OPTIONS]"
        echo
        echo "Options:"
        echo "  --list        Show detected agents and skills without installing"
        echo "  --uninstall   Remove all vela-* skills from agent directories"
        echo "  --force       Overwrite existing skills without checking"
        echo "  --help        Show this help"
        exit 0
        ;;
      *)
        err "Unknown option: $arg"
        exit 1
        ;;
    esac
  done

  case "$action" in
    list)      do_list ;;
    install)   do_install "$force" ;;
    uninstall) do_uninstall ;;
  esac
}

main "$@"
