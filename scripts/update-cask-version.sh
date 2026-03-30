#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/update-cask-version.sh <cask-file> <version> <sha256>
EOF
}

if [[ $# -ne 3 ]]; then
  usage
  exit 1
fi

CASK_FILE="$1"
VERSION="$2"
SHA256="$3"

if [[ ! -f "$CASK_FILE" ]]; then
  echo "Error: Cask file not found: ${CASK_FILE}" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid version format: ${VERSION}" >&2
  exit 1
fi

if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Error: Invalid sha256: ${SHA256}" >&2
  exit 1
fi

ruby - "$CASK_FILE" "$VERSION" "$SHA256" <<'RUBY'
path, version, sha = ARGV
text = File.read(path)

unless text.sub!(/^(\s*version\s+")([^"]+)(")/, "\\1#{version}\\3")
  abort "Failed to update version in #{path}"
end

unless text.sub!(/^(\s*sha256\s+")([^"]+)(")/, "\\1#{sha}\\3")
  abort "Failed to update sha256 in #{path}"
end

File.write(path, text)
RUBY
