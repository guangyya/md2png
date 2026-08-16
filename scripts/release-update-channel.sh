#!/bin/bash
set -euo pipefail

contract_path="scripts/release-update-channel-contract-v1"
expected_contract="md2png stable update channel contract v1"

usage() {
  echo "Usage: $0 prepare-source|validate-app --source-commit SHA --workflow-commit SHA --plist PATH" >&2
  exit 1
}

command="${1:-}"
if [[ "$command" != "prepare-source" && "$command" != "validate-app" ]]; then
  usage
fi
shift

source_commit=""
workflow_commit=""
plist_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-commit)
      source_commit="${2:-}"
      shift 2
      ;;
    --workflow-commit)
      workflow_commit="${2:-}"
      shift 2
      ;;
    --plist)
      plist_path="${2:-}"
      shift 2
      ;;
    *) usage ;;
  esac
done

if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "--source-commit must be a full lowercase commit SHA." >&2
  exit 1
fi
if [[ ! "$workflow_commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "--workflow-commit must be a full lowercase commit SHA." >&2
  exit 1
fi
if [[ ! -f "$plist_path" ]]; then
  echo "--plist must name an existing property list." >&2
  exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$source_commit" ]]; then
  echo "The checked-out release source does not match --source-commit." >&2
  exit 1
fi

git cat-file -e "${workflow_commit}^{commit}"
git merge-base --is-ancestor "$source_commit" "$workflow_commit"
contract_value="$(git show "${workflow_commit}:${contract_path}")"
if [[ "$contract_value" != "$expected_contract" ]]; then
  echo "The trusted workflow commit does not carry the expected update-channel contract." >&2
  exit 1
fi

contract_commits="$(git log --format=%H --diff-filter=A "$workflow_commit" -- "$contract_path")"
if [[ -z "$contract_commits" || "$contract_commits" == *$'\n'* ]]; then
  echo "The update-channel contract must have exactly one introduction commit." >&2
  exit 1
fi
contract_commit="$contract_commits"
contract_parent="$(git rev-parse "${contract_commit}^")"

if git merge-base --is-ancestor "$contract_commit" "$source_commit"; then
  source_generation="contract"
elif git merge-base --is-ancestor "$source_commit" "$contract_parent"; then
  source_generation="legacy"
else
  echo "The release source cannot be ordered against the update-channel contract." >&2
  exit 1
fi

read_channel() {
  /usr/libexec/PlistBuddy -c 'Print :MD2PNGUpdateChannel' "$1" 2>/dev/null
}

if [[ "$command" = "prepare-source" ]]; then
  if [[ "$plist_path" != "Info.plist" ]]; then
    echo "prepare-source may modify only the checked-out Info.plist." >&2
    exit 1
  fi
  source_channel="$(read_channel "$plist_path" || true)"
  if [[ "$source_generation" = "contract" && "$source_channel" != "disabled" ]]; then
    echo "A contract-aware source must default MD2PNGUpdateChannel to disabled." >&2
    exit 1
  fi
  if [[ "$source_generation" = "legacy" && -n "$source_channel" ]]; then
    echo "A legacy source must not define MD2PNGUpdateChannel." >&2
    exit 1
  fi
  if [[ -n "$source_channel" ]]; then
    /usr/libexec/PlistBuddy -c 'Set :MD2PNGUpdateChannel stable' "$plist_path"
  else
    /usr/libexec/PlistBuddy -c 'Add :MD2PNGUpdateChannel string stable' "$plist_path"
  fi
  test "$(read_channel "$plist_path")" = "stable"
  echo "Injected the trusted stable update channel before signing."
  exit 0
fi

app_channel="$(read_channel "$plist_path" || true)"
if /usr/libexec/PlistBuddy -c 'Print :MD2PNGDebugCheckoutID' "$plist_path" >/dev/null 2>&1; then
  echo "A signed stable App must not carry a debug checkout identity." >&2
  exit 1
fi
if [[ -n "$app_channel" ]]; then
  if [[ "$app_channel" != "stable" ]]; then
    echo "The signed App update channel must be exactly stable." >&2
    exit 1
  fi
  exit 0
fi

if [[ "$source_generation" != "legacy" ]]; then
  echo "A contract-aware signed App must carry the stable update channel." >&2
  exit 1
fi
echo "Authorizing a legacy stable App whose source predates the update-channel contract."
