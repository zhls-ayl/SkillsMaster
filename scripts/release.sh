#!/bin/bash
# release.sh — Create git tag and push to GitHub to trigger the Release workflow
#
# Features:
#   1. Check if working directory is clean (prevent forgetting to commit code)
#   2. Check if current branch is pushed to remote
#   3. Validate version format (semantic versioning x.y.z)
#   4. Check if tag already exists (prevent duplicate Release tags)
#   5. Create annotated git tag and push to GitHub
#   6. Pushing will automatically trigger .github/workflows/release.yml workflow
#
# Usage:
#   ./scripts/release.sh 1.0.0                  # Auto-detect GitHub remote and push v1.0.0 tag
#   ./scripts/release.sh 1.0.0 --remote zhls-ayl
#   ./scripts/release.sh 1.0.0 --dry           # Dry run, only check, no execution
#
# Dependencies:
#   - git (version control)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"

# ── Color Definitions ──────────────────────────────────────────────────
# ANSI escape codes for colored terminal output to improve readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color (reset color)

# ── Helper Functions ──────────────────────────────────────────────────
# Unified log output format
info()  { echo -e "${CYAN}==> ${NC}$1"; }
ok()    { echo -e "${GREEN}  ✓ ${NC}$1"; }
warn()  { echo -e "${YELLOW}  ⚠ ${NC}$1"; }
error() { echo -e "${RED}  ✗ ${NC}$1" >&2; }

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

github_repo_url_from_remote() {
    local url="$1"
    local path=""

    case "$url" in
        https://github.com/*)
            path="${url#https://github.com/}"
            ;;
        http://github.com/*)
            path="${url#http://github.com/}"
            ;;
        git@github.com:*)
            path="${url#git@github.com:}"
            ;;
        ssh://git@github.com/*)
            path="${url#ssh://git@github.com/}"
            ;;
        *)
            return 1
            ;;
    esac

    path="${path%.git}"
    echo "https://github.com/${path}"
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
        echo "  GitHub remotes:"
        for remote in "${github_remotes[@]}"; do
            echo "    ${remote}: $(git_remote_url "$remote")"
        done
        exit 1
    fi

    error "No GitHub remote found. Add a GitHub remote or pass --remote <name>."
    exit 1
}

# ── Parse Arguments ──────────────────────────────────────────────────
# $# is bash special variable, representing number of arguments passed
usage() {
    echo "Usage: $0 [version] [--remote <name>] [--dry] [--yes]"
    echo ""
    echo "Examples:"
    echo "  $0                          # Use VERSION file and create the matching tag"
    echo "  $0 1.0.0                    # Create and push v1.0.0 to the only GitHub remote"
    echo "  $0 v1.0.0                   # Same as above (v prefix is optional)"
    echo "  $0 1.0.0 --remote zhls-ayl  # Push Release tag to a specific GitHub remote"
    echo "  $0 1.0.0 --dry              # Dry run, check only"
    echo "  $0 1.0.0 --yes              # Non-interactive mode, auto-confirm prompts"
    echo ""
    echo "Recent tags:"
    git tag --sort=-creatordate | head -5 || echo "  (no tags yet)"
}

INPUT=""
DRY_RUN=false
AUTO_CONFIRM=false
RELEASE_REMOTE="${RELEASE_REMOTE:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry)
            DRY_RUN=true
            shift
            ;;
        --yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --remote)
            if [[ $# -lt 2 ]]; then
                error "--remote requires a value"
                usage
                exit 1
            fi
            RELEASE_REMOTE="$2"
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
            if [[ -n "$INPUT" ]]; then
                error "Multiple version arguments provided: '${INPUT}' and '$1'"
                usage
                exit 1
            fi
            INPUT="$1"
            shift
            ;;
    esac
done

if [[ -z "$INPUT" ]]; then
    if [[ ! -f "$VERSION_FILE" ]]; then
        error "Version is required and VERSION file is missing: ${VERSION_FILE}"
        usage
        exit 1
    fi
    INPUT="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

# ── Validate Version Format ────────────────────────────────────────────
# Semantic Versioning format: Major.Minor.Patch
# Supports two input formats: v1.0.0 or 1.0.0, handled uniformly
# ${INPUT#v} is bash parameter expansion syntax, removing prefix "v" (if present)
VERSION="${INPUT#v}"
TAG="v${VERSION}"

if [[ -f "$VERSION_FILE" ]]; then
    VERSION_FROM_FILE="$(tr -d '[:space:]' < "$VERSION_FILE")"
    if [[ "$VERSION_FROM_FILE" != "$VERSION" ]]; then
        error "Provided version '${VERSION}' does not match VERSION file '${VERSION_FROM_FILE}'."
        exit 1
    fi
fi

# =~ is bash regex match operator
# ^[0-9]+\.[0-9]+\.[0-9]+$ matches x.y.z format (digits only)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid version format: '${INPUT}'"
    echo "  Expected: x.y.z or vx.y.z (e.g. 1.0.0, v0.2.1)"
    exit 1
fi

ok "Version format valid: ${TAG}"

# ── Check if inside git repository ────────────────────────────────────
# rev-parse --git-dir checks if current directory is inside a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not a git repository"
    exit 1
fi

# ── Check if working directory is clean ──────────────────────────────────────
# git status --porcelain outputs status in machine-readable format
# If output is not empty, there are uncommitted changes
if [[ -n "$(git status --porcelain)" ]]; then
    error "Working directory is not clean. Please commit or stash changes first."
    echo ""
    git status --short
    exit 1
fi

ok "Working directory is clean"

# ── Detect release remote ──────────────────────────────────────────────
RELEASE_REMOTE="$(detect_release_remote "$RELEASE_REMOTE")"
RELEASE_REMOTE_URL="$(git_remote_url "$RELEASE_REMOTE")"
REPO_URL="$(github_repo_url_from_remote "$RELEASE_REMOTE_URL")"

ok "Release remote: ${RELEASE_REMOTE} (${RELEASE_REMOTE_URL})"

# ── Check current branch ──────────────────────────────────────────────
# git branch --show-current shows current branch name
BRANCH=$(git branch --show-current)
if [[ -z "$BRANCH" ]]; then
    error "Detached HEAD is not supported. Checkout a branch before creating a Release."
    exit 1
fi
info "Current branch: ${BRANCH}"

# Usually recommended to Release from main branch, but not enforced
if [[ "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
    warn "Not on main/master branch (current: ${BRANCH})"
    if $AUTO_CONFIRM; then
        warn "Auto-confirm enabled: continue from non-main/master branch."
    else
        # -r allows read backslash, -p shows prompt
        read -r -p "  Continue anyway? [y/N] " confirm
        if [[ "$confirm" != [yY] ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
fi

# ── Check if local is in sync with release remote ──────────────────────────
# Ensure the Release tag points to a commit already available on the GitHub remote.
LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD="$(git ls-remote --heads "$RELEASE_REMOTE" "refs/heads/${BRANCH}" | awk '{print $1}')"

if [[ -z "$REMOTE_HEAD" ]]; then
    error "Branch '${BRANCH}' does not exist on remote '${RELEASE_REMOTE}'."
    echo "  Push it first:"
    echo "    git push ${RELEASE_REMOTE} ${BRANCH}"
    exit 1
fi

if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
    error "Local branch is out of sync with ${RELEASE_REMOTE}/${BRANCH}."
    echo "  Please push the Release commit first:"
    echo "    git push ${RELEASE_REMOTE} ${BRANCH}"
    exit 1
fi

ok "Branch is in sync with ${RELEASE_REMOTE}/${BRANCH}"

# ── Check if tag already exists locally or on release remote ──────────
if git rev-parse "$TAG" > /dev/null 2>&1; then
    error "Tag '${TAG}' already exists!"
    echo "  To delete and recreate:"
    echo "    git tag -d ${TAG}"
    echo "    git push ${RELEASE_REMOTE} :refs/tags/${TAG}"
    exit 1
fi

if [[ -n "$(git ls-remote --tags "$RELEASE_REMOTE" "refs/tags/${TAG}" "refs/tags/${TAG}^{}")" ]]; then
    error "Tag '${TAG}' already exists on remote '${RELEASE_REMOTE}'!"
    echo "  To delete and recreate:"
    echo "    git push ${RELEASE_REMOTE} :refs/tags/${TAG}"
    exit 1
fi

ok "Tag '${TAG}' is available locally and on ${RELEASE_REMOTE}"

# ── Show Release Summary ──────────────────────────────────────────────
echo ""
info "Release Summary"
echo "  Tag:      ${TAG}"
echo "  Remote:   ${RELEASE_REMOTE}"
echo "  Branch:   ${BRANCH}"
# git rev-parse --short HEAD outputs 7-char short hash, more readable
echo "  Commit:   $(git rev-parse --short HEAD)"
# git log -1 --format=%s gets latest commit subject (%s = subject)
echo "  Message:  $(git log -1 --format=%s)"
echo ""

# ── Dry run check ──────────────────────────────────────────────
if $DRY_RUN; then
    info "Dry run complete. No changes made."
    echo "  Remove --dry to create and push the tag."
    exit 0
fi

# ── Confirm Release ──────────────────────────────────────────────────
if $AUTO_CONFIRM; then
    info "Auto-confirm enabled: creating and pushing ${TAG}."
else
    read -r -p "Create and push ${TAG}? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ── Create annotated tag ──────────────────────────────────────────
# -a creates annotated tag, storing extra metadata (author, date, message)
# Compared to lightweight tag, annotated tag is better for Release
# -m specifies tag message
info "Creating tag ${TAG} ..."
git tag -a "$TAG" -m "Release ${TAG}"
ok "Tag created"

# ── Push tag to remote ───────────────────────────────────────────
# Push only specific tag, not --tags (avoid pushing all local tags)
info "Pushing ${TAG} to ${RELEASE_REMOTE} ..."
git push "$RELEASE_REMOTE" "$TAG"
ok "Tag pushed"

# ── Show Results ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}==> Release ${TAG} triggered! ${NC}"
echo ""

echo "  Actions:  ${REPO_URL}/actions"
echo "  Release:  ${REPO_URL}/releases/tag/${TAG}"
echo "  Tags:     ${REPO_URL}/tags"

echo ""
echo "  The Release workflow will:"
echo "    1. Run tests"
echo "    2. Build universal / arm64 / x86_64 release artifacts"
echo "    3. Create GitHub Release with zip and dmg downloads"
