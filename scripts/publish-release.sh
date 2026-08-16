#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

node_binary="${NODE:-node}"
sign_identity="${SIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-MDPNGNotary}"
gh_host="${GH_HOST:-github.com}"
gh_repo="${GH_REPO:-}"
project_url="${PROJECT_URL:-}"
bundle_identifier="${BUNDLE_IDENTIFIER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
tag="v${version}"
asset_contract_json="$("$node_binary" scripts/release-assets.mjs json --version "$version")"
asset_value_by_key() {
  jq -er --arg key "$1" --arg field "$2" \
    '.assets[] | select(.key == $key) | .[$field]' <<< "$asset_contract_json"
}
asset_value_by_name() {
  jq -er --arg name "$1" --arg field "$2" \
    '.assets[] | select(.name == $name) | .[$field]' <<< "$asset_contract_json"
}
release_zip="$(asset_value_by_key releaseZip sourcePath)"
appcast="$(jq -r '.assets[] | select(.key == "appcast") | .sourcePath' <<< "$asset_contract_json")"
release_dmg="$(asset_value_by_key releaseDmg sourcePath)"
latest_dmg="$(asset_value_by_key latestDmg sourcePath)"
notes_file=".build/release-notes-${version}.md"
coverage_json="$(asset_value_by_key coverageJson sourcePath)"
coverage_markdown="$(asset_value_by_key coverageMarkdown sourcePath)"

if [[ -n "${TEST_UPDATE_VERSION:-}" || -n "${TEST_UPDATE_STATE:-}" ]]; then
  echo "TEST_UPDATE_VERSION and TEST_UPDATE_STATE are only for local app/run builds." >&2
  exit 1
fi

if [[ -n "$appcast" && -z "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_EDDSA_PRIVATE_KEY is required to publish a signed update feed." >&2
  exit 1
fi

if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "CFBundleShortVersionString must be a stable semantic version such as 0.2.0." >&2
  exit 1
fi

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "CFBundleVersion must be a positive, monotonically increasing integer." >&2
  exit 1
fi

if [[ ! "$gh_host" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "GH_HOST must be a hostname such as github.com." >&2
  exit 1
fi

if [[ ! "$gh_repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GH_REPO is required in OWNER/REPOSITORY form." >&2
  exit 1
fi

repo_ref="${gh_host}/${gh_repo}"
if [[ -z "$project_url" ]]; then
  project_url="https://${repo_ref}"
fi
project_url="${project_url%/}"

if [[ ! "$project_url" =~ ^https://[^/?#]+/[^/?#]+/[^/?#]+$ ]]; then
  echo "PROJECT_URL must be an HTTPS repository URL without a query or fragment." >&2
  exit 1
fi

if [[ "$sign_identity" != "Developer ID Application:"* ]]; then
  echo "SIGN_IDENTITY must be a Developer ID Application identity." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"${sign_identity}\""; then
  echo "The requested Developer ID Application identity is not installed." >&2
  exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Release publishing must run from main." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit all changes before publishing a release." >&2
  exit 1
fi

git fetch origin main --tags
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Local main must exactly match origin/main." >&2
  exit 1
fi

mkdir -p .build
if ! ./scripts/release-notes.sh "$version" CHANGELOG.md > "$notes_file"; then
  echo "CHANGELOG.md has no section for ${version}." >&2
  exit 1
fi
if [[ ! -s "$notes_file" ]]; then
  echo "Release notes for ${version} are empty." >&2
  exit 1
fi

gh auth status --hostname "$gh_host" >/dev/null
existing_release_tags="$(
  gh release list --repo "$repo_ref" --limit 100 --json tagName --jq '.[].tagName'
)"
if grep -Fxq "$tag" <<< "$existing_release_tags"; then
  echo "Release ${tag} already exists." >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null \
  && [[ "$(git rev-list -n 1 "$tag")" != "$(git rev-parse HEAD)" ]]; then
  echo "Existing tag ${tag} does not point to HEAD." >&2
  exit 1
fi

coverage_xcode_version="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
if [[ "$coverage_xcode_version" != "26.2" ]]; then
  echo "Release coverage requires Xcode 26.2; selected Xcode is ${coverage_xcode_version:-unknown}." >&2
  exit 1
fi

make coverage
make coverage-validate
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Coverage generation changed the clean release worktree." >&2
  git status --short >&2
  exit 1
fi

make notarize \
  SIGN_IDENTITY="$sign_identity" \
  NOTARY_PROFILE="$notary_profile" \
  PROJECT_URL="$project_url" \
  UPDATE_CHANNEL=stable \
  BUNDLE_IDENTIFIER="$bundle_identifier" \
  RELEASE_SUFFIX=developer-id
if [[ -n "$appcast" ]]; then
  GH_REPO="$gh_repo" PROJECT_URL="$project_url" ./scripts/generate-appcast.sh
fi

release_artifacts=("$release_zip" "$release_dmg" "$coverage_json" "$coverage_markdown")
if [[ -n "$appcast" ]]; then
  release_artifacts+=("$appcast")
fi
for artifact in "${release_artifacts[@]}"; do
  if [[ ! -s "$artifact" ]]; then
    echo "Expected release artifact is missing or empty: ${artifact}" >&2
    exit 1
  fi
done

cp -f "$release_dmg" "$latest_dmg"
if ! cmp -s "$release_dmg" "$latest_dmg"; then
  echo "The stable DMG alias does not match the versioned DMG." >&2
  exit 1
fi

if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  git tag -a "$tag" -m "md2png ${version}"
fi

git push origin "$tag"
release_uploads=()
while IFS= read -r asset; do
  source_path="$(jq -r .sourcePath <<< "$asset")"
  label="$(jq -r .label <<< "$asset")"
  release_uploads+=("${source_path}#${label}")
done < <(jq -c '.assets[]' <<< "$asset_contract_json")
gh release create "$tag" \
  "${release_uploads[@]}" \
  --repo "$repo_ref" \
  --title "md2png ${version}" \
  --notes-file "$notes_file" \
  --verify-tag \
  --latest \
  --fail-on-no-commits

release_endpoint="repos/${gh_repo}/releases/tags/${tag}"
release_json="$(gh api --hostname "$gh_host" "$release_endpoint")"
published_names="$(jq -r '.assets[].name' <<< "$release_json" | LC_ALL=C sort)"
expected_names="$(jq -r '.assets[].name' <<< "$asset_contract_json" | LC_ALL=C sort)"
if [[ "$published_names" != "$expected_names" ]]; then
  echo "Published Release has unexpected or missing assets." >&2
  diff -u <(printf '%s\n' "$expected_names") <(printf '%s\n' "$published_names") >&2 || true
  exit 1
fi
while IFS= read -r name; do
  asset_json="$(jq -c --arg name "$name" '.assets[] | select(.name == $name)' <<< "$release_json")"
  test "$(jq -r .label <<< "$asset_json")" = "$(asset_value_by_name "$name" label)"
  test "$(jq -r .content_type <<< "$asset_json")" = "$(asset_value_by_name "$name" contentType)"
done < <(jq -r '.assets[].name' <<< "$asset_contract_json")

versioned_dmg_name="$(asset_value_by_key releaseDmg name)"
versioned_dmg_count="$(
  jq --arg name "$versioned_dmg_name" '[.assets[] | select(.name == $name)] | length' <<< "$release_json"
)"
if [[ "$versioned_dmg_count" != "1" ]]; then
  echo "Published release must contain exactly one versioned DMG asset." >&2
  exit 1
fi

versioned_dmg_type="$(
  jq -r --arg name "$versioned_dmg_name" '.assets[] | select(.name == $name) | .content_type' <<< "$release_json"
)"
versioned_dmg_size="$(
  jq -r --arg name "$versioned_dmg_name" '.assets[] | select(.name == $name) | .size' <<< "$release_json"
)"
versioned_dmg_digest="$(
  jq -r --arg name "$versioned_dmg_name" '.assets[] | select(.name == $name) | .digest' <<< "$release_json"
)"
if [[ "$versioned_dmg_type" != "$(asset_value_by_key releaseDmg contentType)" ]]; then
  echo "Published versioned DMG has unexpected content type: ${versioned_dmg_type}" >&2
  exit 1
fi
if [[ ! "$versioned_dmg_size" =~ ^[1-9][0-9]*$ ]]; then
  echo "Published versioned DMG has an invalid size: ${versioned_dmg_size}" >&2
  exit 1
fi
if [[ ! "$versioned_dmg_digest" =~ ^sha256:[0-9a-fA-F]{64}$ ]]; then
  echo "Published versioned DMG is missing a valid SHA-256 digest." >&2
  exit 1
fi

latest_release_tag="$(
  gh api --hostname "$gh_host" "repos/${gh_repo}/releases/latest" --jq .tag_name
)"
if [[ "$latest_release_tag" != "$tag" ]]; then
  echo "The latest stable Release is ${latest_release_tag}, expected ${tag}." >&2
  exit 1
fi

release_url="$(gh release view "$tag" --repo "$repo_ref" --json url --jq .url)"
stable_dmg_url="${project_url}/releases/latest/download/$(asset_value_by_key latestDmg name)"
printf 'Release: %s\nLatest DMG: %s\n' "$release_url" "$stable_dmg_url"
