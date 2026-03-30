#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
CHANGELOG_FILE="${REPO_ROOT}/CHANGELOG.md"
WORKFLOW_NAME="Release Orchestrator"
TAP_REPO_DEFAULT="zhls-ayl/homebrew-skillsmaster"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}==> ${NC}$1"; }
ok()    { echo -e "${GREEN}  ✓ ${NC}$1"; }
warn()  { echo -e "${YELLOW}  ⚠ ${NC}$1"; }
error() { echo -e "${RED}  ✗ ${NC}$1" >&2; }

usage() {
  cat <<'EOF'
Usage: ./scripts/ship.sh [version] [--remote <name>] [--dry] [--yes] [--no-wait] [--commit-message "<message>"]

Examples:
  ./scripts/ship.sh
  ./scripts/ship.sh 1.2.3
  ./scripts/ship.sh 1.2.3 --dry
  ./scripts/ship.sh 1.2.3 --remote zhls-ayl --yes
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Required command not found: ${cmd}"
    exit 1
  fi
}

read_version_file() {
  if [[ ! -f "$VERSION_FILE" ]]; then
    error "VERSION file not found: ${VERSION_FILE}"
    exit 1
  fi

  tr -d '[:space:]' < "$VERSION_FILE"
}

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid version format: ${version}"
    exit 1
  fi
}

git_remote_url() {
  git config --get "remote.$1.url" 2>/dev/null || true
}

is_github_remote_url() {
  case "$1" in
    https://github.com/*|http://github.com/*|git@github.com:*|ssh://git@github.com/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

detect_release_remote() {
  local requested_remote="$1"
  local remote=""
  local remote_url=""
  local github_remotes=()

  if [[ -n "$requested_remote" ]]; then
    remote_url="$(git_remote_url "$requested_remote")"
    if [[ -z "$remote_url" ]]; then
      error "Remote '${requested_remote}' does not exist."
      exit 1
    fi
    if ! is_github_remote_url "$remote_url"; then
      error "Remote '${requested_remote}' is not a GitHub remote: ${remote_url}"
      exit 1
    fi
    echo "$requested_remote"
    return 0
  fi

  while IFS= read -r remote; do
    [[ -z "$remote" ]] && continue
    remote_url="$(git_remote_url "$remote")"
    if is_github_remote_url "$remote_url"; then
      github_remotes+=("$remote")
    fi
  done < <(git remote)

  if [[ ${#github_remotes[@]} -eq 1 ]]; then
    echo "${github_remotes[0]}"
    return 0
  fi

  if [[ ${#github_remotes[@]} -gt 1 ]]; then
    error "Multiple GitHub remotes found. Please specify one with --remote."
    exit 1
  fi

  error "No GitHub remote found."
  exit 1
}

ensure_changelog_section() {
  local version="$1"
  if ! grep -q "^## \[${version}\]" "$CHANGELOG_FILE"; then
    error "CHANGELOG.md is missing section [${version}]"
    exit 1
  fi
}

find_or_create_release_pr() {
  local repo="$1"
  local branch="$2"
  local version="$3"
  local pr_number=""

  pr_number="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[0].number // empty')"
  if [[ -n "$pr_number" ]]; then
    ok "Reusing open PR #${pr_number} for ${branch}" >&2
    echo "$pr_number"
    return 0
  fi

  pr_number="$(gh pr create \
    --repo "$repo" \
    --base main \
    --head "$branch" \
    --title "chore: prepare v${version} release" \
    --body $'## Summary\n- prepare release `v'"${version}"$'`\n- ensure `VERSION` and `CHANGELOG.md` are aligned before tagging\n- hand off tagging / release / cask sync to Release Orchestrator')"
  echo "${pr_number##*/}"
}

wait_for_workflow_run() {
  local repo="$1"
  local version="$2"
  local run_id=""

  for _ in $(seq 1 60); do
    run_id="$(gh run list --repo "$repo" --workflow "$WORKFLOW_NAME" --limit 20 --json databaseId,event,displayTitle --jq ".[] | select(.event == \"workflow_dispatch\" and (.displayTitle | contains(\"${version}\"))) | .databaseId" | head -n 1)"
    if [[ -n "$run_id" ]]; then
      gh run watch "$run_id" --repo "$repo" --exit-status
      return 0
    fi
    sleep 5
  done

  error "Unable to locate Release Orchestrator workflow run for ${version}"
  exit 1
}

main() {
  require_cmd git
  require_cmd gh

  local version_arg=""
  local release_remote="${RELEASE_REMOTE:-}"
  local tap_repo="${TAP_REPO_DEFAULT}"
  local auto_confirm=false
  local dry_run=false
  local wait_for_run=true
  local commit_message=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --remote)
        release_remote="$2"
        shift 2
        ;;
      --yes)
        auto_confirm=true
        shift
        ;;
      --dry)
        dry_run=true
        shift
        ;;
      --no-wait)
        wait_for_run=false
        shift
        ;;
      --commit-message)
        commit_message="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        error "Unknown argument: $1"
        usage
        exit 1
        ;;
      *)
        if [[ -n "$version_arg" ]]; then
          error "Multiple version arguments provided: ${version_arg} and $1"
          exit 1
        fi
        version_arg="${1#v}"
        shift
        ;;
    esac
  done

  local current_version version
  current_version="$(read_version_file)"
  version="${version_arg:-$current_version}"

  validate_version "$version"
  ensure_changelog_section "$version"
  gh auth status >/dev/null

  local repo branch is_main dirty needs_release_pr=false release_pr_number="0" release_branch
  repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
  release_remote="$(detect_release_remote "$release_remote")"
  branch="$(git branch --show-current)"
  is_main=false
  [[ "$branch" == "main" || "$branch" == "master" ]] && is_main=true
  dirty=false
  [[ -n "$(git status --porcelain)" ]] && dirty=true

  if ! $is_main || $dirty || [[ "$current_version" != "$version" ]]; then
    needs_release_pr=true
  fi

  if $dry_run; then
    echo "Version:              ${version}"
    echo "Release remote:       ${release_remote}"
    echo "Current branch:       ${branch}"
    echo "Needs release PR:     ${needs_release_pr}"
    echo "Will wait for run:    ${wait_for_run}"
    echo "Tap repo:             ${tap_repo}"
    exit 0
  fi

  if $needs_release_pr; then
    release_branch="$branch"

    if $is_main; then
      release_branch="codex/release-v${version//./-}"
      git switch -C "$release_branch"
      branch="$release_branch"
    fi

    if [[ "$current_version" != "$version" ]]; then
      printf '%s\n' "$version" > "$VERSION_FILE"
      ok "Updated VERSION to ${version}"
    fi

    if [[ -n "$(git status --porcelain)" ]]; then
      git add -A
      if ! git diff --cached --quiet; then
        local message
        message="${commit_message:-chore: prepare v${version} release}"
        git commit -m "$message"
        ok "Created release prep commit"
      fi
    fi

    if $auto_confirm; then
      git push -u "$release_remote" "$branch"
    else
      warn "About to push release branch '${branch}' to ${release_remote}"
      read -r -p "Continue? [y/N] " confirm
      if [[ "$confirm" != [yY] ]]; then
        echo "Aborted."
        exit 0
      fi
      git push -u "$release_remote" "$branch"
    fi

    release_pr_number="$(find_or_create_release_pr "$repo" "$branch" "$version")"
    gh pr merge "$release_pr_number" --repo "$repo" --auto --merge
    ok "Release prep PR #${release_pr_number} is set to auto-merge"
  else
    ok "Current main is already ready for v${version}; skipping release prep PR"
  fi

  gh workflow run release-orchestrator.yml \
    --repo "$repo" \
    -f version="$version" \
    -f release_pr_number="$release_pr_number" \
    -f tap_repo="$tap_repo"
  ok "Dispatched ${WORKFLOW_NAME}"

  if $wait_for_run; then
    wait_for_workflow_run "$repo" "$version"
  fi
}

main "$@"
