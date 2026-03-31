#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${VERSION:?VERSION is required}"
RELEASE_PR_NUMBER="${RELEASE_PR_NUMBER:-0}"
TAP_REPO="${TAP_REPO:?TAP_REPO is required}"
RELEASE_SYNC_TOKEN="${RELEASE_SYNC_TOKEN:?RELEASE_SYNC_TOKEN is required}"
CURRENT_REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
VERSION_FILE="${REPO_ROOT}/VERSION"
CHANGELOG_FILE="${REPO_ROOT}/CHANGELOG.md"
CURRENT_CASK_FILE="${REPO_ROOT}/homebrew/skillsmaster.rb"
TAG="v${VERSION}"
UNIVERSAL_ASSET="SkillsMaster-v${VERSION}-universal.zip"
CURRENT_CASK_BRANCH="codex/sync-homebrew-${VERSION//./-}"
TAP_CASK_BRANCH="codex/sync-skillsmaster-${VERSION//./-}"
BOT_NAME="github-actions[bot]"
BOT_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}==> ${NC}$1"; }
ok()    { echo -e "${GREEN}  ✓ ${NC}$1"; }
warn()  { echo -e "${YELLOW}  ⚠ ${NC}$1"; }
error() { echo -e "${RED}  ✗ ${NC}$1" >&2; }

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Required command not found: ${cmd}"
    exit 1
  fi
}

validate_version() {
  if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid VERSION: ${VERSION}"
    exit 1
  fi
}

gh_repo_auth_url() {
  local repo="$1"
  echo "https://x-access-token:${RELEASE_SYNC_TOKEN}@github.com/${repo}.git"
}

wait_for_pr_merge() {
  local repo="$1"
  local pr_number="$2"

  if [[ "$pr_number" == "0" ]]; then
    return 0
  fi

  local state merged_at
  for _ in $(seq 1 180); do
    state="$(gh pr view "$pr_number" --repo "$repo" --json state --jq '.state')"
    merged_at="$(gh pr view "$pr_number" --repo "$repo" --json mergedAt --jq '.mergedAt // ""')"

    if [[ -n "$merged_at" ]]; then
      ok "PR #${pr_number} in ${repo} has merged"
      return 0
    fi

    if [[ "$state" == "CLOSED" ]]; then
      error "PR #${pr_number} in ${repo} was closed without merge"
      exit 1
    fi

    sleep 10
  done

  error "Timed out waiting for PR #${pr_number} in ${repo} to merge"
  exit 1
}

merge_pr_with_wait() {
  local repo="$1"
  local pr_number="$2"
  local last_output=""
  local attempt_file

  attempt_file="$(mktemp)"

  for _ in $(seq 1 180); do
    local state merged_at
    state="$(gh pr view "$pr_number" --repo "$repo" --json state --jq '.state')"
    merged_at="$(gh pr view "$pr_number" --repo "$repo" --json mergedAt --jq '.mergedAt // ""')"

    if [[ -n "$merged_at" ]]; then
      ok "PR #${pr_number} in ${repo} has merged"
      rm -f "${attempt_file}"
      return 0
    fi

    if [[ "$state" == "CLOSED" ]]; then
      error "PR #${pr_number} in ${repo} was closed without merge"
      rm -f "${attempt_file}"
      exit 1
    fi

    if GH_TOKEN="${RELEASE_SYNC_TOKEN}" gh pr merge "$pr_number" --repo "$repo" --merge --delete-branch >"${attempt_file}" 2>&1; then
      cat "${attempt_file}" >&2
      ok "Merged PR #${pr_number} in ${repo}"
      rm -f "${attempt_file}"
      return 0
    fi

    last_output="$(cat "${attempt_file}")"
    sleep 10
  done

  error "Timed out waiting to merge PR #${pr_number} in ${repo}"
  if [[ -n "$last_output" ]]; then
    echo "${last_output}" >&2
  fi
  rm -f "${attempt_file}"
  exit 1
}

resolve_release_commit() {
  if [[ "$RELEASE_PR_NUMBER" == "0" ]]; then
    git fetch origin main --tags
    git rev-parse origin/main
    return 0
  fi

  local merge_commit
  for _ in $(seq 1 180); do
    merge_commit="$(gh pr view "$RELEASE_PR_NUMBER" --repo "$CURRENT_REPO" --json mergeCommit --jq '.mergeCommit.oid // ""')"
    if [[ -n "$merge_commit" ]]; then
      echo "$merge_commit"
      return 0
    fi
    sleep 10
  done

  error "Unable to resolve merge commit for PR #${RELEASE_PR_NUMBER}"
  exit 1
}

validate_release_sources() {
  local release_commit="$1"
  local file_version

  file_version="$(git show "${release_commit}:VERSION" | tr -d '[:space:]')"
  if [[ "$file_version" != "$VERSION" ]]; then
    error "VERSION at ${release_commit} is '${file_version}', expected '${VERSION}'"
    exit 1
  fi

  if ! git show "${release_commit}:CHANGELOG.md" | grep -q "^## \[${VERSION}\]"; then
    error "CHANGELOG.md at ${release_commit} is missing section [${VERSION}]"
    exit 1
  fi

  ok "Validated VERSION and CHANGELOG at ${release_commit}"
}

create_tag_if_needed() {
  local release_commit="$1"

  if git ls-remote --tags origin "refs/tags/${TAG}" "refs/tags/${TAG}^{}" | grep -q .; then
    ok "Tag ${TAG} already exists on origin"
    return 0
  fi

  info "Creating tag ${TAG} at ${release_commit}"
  git tag -a "${TAG}" "${release_commit}" -m "Release ${TAG}"
  git push origin "${TAG}"
  ok "Tag ${TAG} pushed"
}

wait_for_release_workflow() {
  local run_id=""

  for _ in $(seq 1 60); do
    run_id="$(gh run list --repo "$CURRENT_REPO" --workflow Release --limit 20 --json databaseId,headBranch,event --jq ".[] | select(.headBranch == \"${TAG}\" and .event == \"push\") | .databaseId" | head -n 1)"
    if [[ -n "$run_id" ]]; then
      break
    fi
    sleep 10
  done

  if [[ -z "$run_id" ]]; then
    error "Release workflow for ${TAG} did not appear"
    exit 1
  fi

  info "Watching Release workflow run ${run_id}"
  gh run watch "$run_id" --repo "$CURRENT_REPO" --exit-status
}

resolve_release_sha() {
  local digest=""

  for _ in $(seq 1 60); do
    digest="$(gh release view "${TAG}" --repo "$CURRENT_REPO" --json assets --jq ".assets[] | select(.name == \"${UNIVERSAL_ASSET}\") | .digest" 2>/dev/null | head -n 1)"
    if [[ -n "$digest" ]]; then
      echo "${digest#sha256:}"
      return 0
    fi
    sleep 5
  done

  error "Unable to resolve digest for ${UNIVERSAL_ASSET}"
  exit 1
}

sync_current_repo_cask() {
  local sha256="$1"
  local pr_number=""

  git fetch origin main
  git switch -C "${CURRENT_CASK_BRANCH}" origin/main

  "${REPO_ROOT}/scripts/update-cask-version.sh" "${CURRENT_CASK_FILE}" "${VERSION}" "${sha256}"

  if git diff --quiet -- "${CURRENT_CASK_FILE}"; then
    ok "Current repository cask already matches ${VERSION}"
    git switch -C main origin/main
    return 0
  fi

  git add "${CURRENT_CASK_FILE}"
  git commit -m "chore: sync homebrew cask to ${VERSION}"
  git push --force-with-lease origin "${CURRENT_CASK_BRANCH}"

  pr_number="$(gh pr list --repo "$CURRENT_REPO" --head "${CURRENT_CASK_BRANCH}" --state open --json number --jq '.[0].number // empty')"
  if [[ -z "$pr_number" ]]; then
    pr_number="$(gh pr create \
      --repo "$CURRENT_REPO" \
      --base main \
      --head "${CURRENT_CASK_BRANCH}" \
      --title "chore: sync homebrew cask to ${VERSION}" \
      --body $'## Summary\n- update the in-repo Homebrew cask template to `'"${VERSION}"$'`\n- sync the cask `sha256` to the published `'"${UNIVERSAL_ASSET}"$'` asset\n\n## Verification\n- GitHub Release `'"${TAG}"$'` succeeded\n- confirmed release asset digest: `'"${sha256}"$'`')"
  else
    ok "Reusing existing current-repo cask PR #${pr_number}"
  fi

  merge_pr_with_wait "$CURRENT_REPO" "${pr_number}"
  git fetch origin main
  git switch -C main origin/main
}

sync_tap_repo_cask() {
  local sha256="$1"
  local tap_dir
  local pr_number=""
  cleanup_tap_dir() {
    if [[ -n "${tap_dir:-}" ]]; then
      rm -rf "${tap_dir}"
    fi
    trap - RETURN
  }

  tap_dir="$(mktemp -d)"
  trap cleanup_tap_dir RETURN

  GH_TOKEN="${RELEASE_SYNC_TOKEN}" gh repo clone "${TAP_REPO}" "${tap_dir}" -- --quiet

  git -C "${tap_dir}" config user.name "${BOT_NAME}"
  git -C "${tap_dir}" config user.email "${BOT_EMAIL}"
  git -C "${tap_dir}" remote set-url origin "$(gh_repo_auth_url "${TAP_REPO}")"
  git -C "${tap_dir}" fetch origin main
  git -C "${tap_dir}" switch -C "${TAP_CASK_BRANCH}" origin/main

  "${REPO_ROOT}/scripts/update-cask-version.sh" "${tap_dir}/Casks/skillsmaster.rb" "${VERSION}" "${sha256}"

  if git -C "${tap_dir}" diff --quiet -- Casks/skillsmaster.rb; then
    ok "Tap repository cask already matches ${VERSION}"
    cleanup_tap_dir
    return 0
  fi

  git -C "${tap_dir}" add Casks/skillsmaster.rb
  git -C "${tap_dir}" commit -m "chore: sync skillsmaster cask to ${VERSION}"
  git -C "${tap_dir}" push --force-with-lease origin "${TAP_CASK_BRANCH}"

  pr_number="$(GH_TOKEN="${RELEASE_SYNC_TOKEN}" gh pr list --repo "${TAP_REPO}" --head "${TAP_CASK_BRANCH}" --state open --json number --jq '.[0].number // empty')"
  if [[ -z "$pr_number" ]]; then
    pr_number="$(GH_TOKEN="${RELEASE_SYNC_TOKEN}" gh pr create \
      --repo "${TAP_REPO}" \
      --base main \
      --head "${TAP_CASK_BRANCH}" \
      --title "chore: sync skillsmaster cask to ${VERSION}" \
      --body $'## Summary\n- update the tap cask to `'"${VERSION}"$'`\n- sync the `sha256` to the published `'"${UNIVERSAL_ASSET}"$'` asset\n\n## Verification\n- GitHub Release `'"${TAG}"$'` succeeded\n- confirmed release asset digest: `'"${sha256}"$'`')"
  else
    ok "Reusing existing tap-repo PR #${pr_number}"
  fi

  merge_pr_with_wait "${TAP_REPO}" "${pr_number}"
  cleanup_tap_dir
}

write_summary() {
  local sha256="$1"

  {
    echo "## Release Automation Completed"
    echo ""
    echo "- Version: \`${VERSION}\`"
    echo "- Tag: \`${TAG}\`"
    echo "- Release: https://github.com/${CURRENT_REPO}/releases/tag/${TAG}"
    echo "- Universal asset digest: \`${sha256}\`"
    echo "- Tap repo: \`${TAP_REPO}\`"
  } >> "${GITHUB_STEP_SUMMARY}"
}

main() {
  require_cmd git
  require_cmd gh
  require_cmd ruby
  validate_version

  git config user.name "${BOT_NAME}"
  git config user.email "${BOT_EMAIL}"
  git remote set-url origin "$(gh_repo_auth_url "${CURRENT_REPO}")"

  if [[ "$RELEASE_PR_NUMBER" != "0" ]]; then
    info "Waiting for release prep PR #${RELEASE_PR_NUMBER} to merge"
    wait_for_pr_merge "${CURRENT_REPO}" "${RELEASE_PR_NUMBER}"
  else
    info "No release prep PR provided; releasing current main"
  fi

  local release_commit
  release_commit="$(resolve_release_commit)"
  validate_release_sources "${release_commit}"
  create_tag_if_needed "${release_commit}"
  wait_for_release_workflow

  local sha256
  sha256="$(resolve_release_sha)"
  ok "Resolved universal asset digest: ${sha256}"

  sync_current_repo_cask "${sha256}"
  sync_tap_repo_cask "${sha256}"
  write_summary "${sha256}"
}

main "$@"
