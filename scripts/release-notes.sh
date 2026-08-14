#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 VERSION CHANGELOG" >&2
  exit 2
fi

release_version="$1"
changelog_path="$2"

awk -v version="$release_version" '
  index($0, "## [" version "]") == 1 {
    found = 1
    next
  }
  found && /^## \[/ {
    exit
  }
  found {
    print
  }
  END {
    if (!found) {
      exit 1
    }
  }
' "$changelog_path"
