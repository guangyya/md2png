#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

sign_identity="${SIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-MDPNGNotary}"
gh_host="${GH_HOST:-github.com}"
gh_repo="${GH_REPO:-}"
project_url="${PROJECT_URL:-}"
bundle_identifier="${BUNDLE_IDENTIFIER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
tag="v${version}"
artifact_base="md2png-${version}-macOS-arm64-developer-id"
release_zip="dist/${artifact_base}.zip"
release_dmg="dist/${artifact_base}.dmg"
latest_dmg="dist/md2png-latest.dmg"
notes_file=".build/release-notes-${version}.md"
coverage_json=".build/coverage/md2png-${version}-coverage.json"
coverage_markdown=".build/coverage/md2png-${version}-coverage.md"

if [[ -n "${TEST_UPDATE_VERSION:-}" || -n "${TEST_UPDATE_STATE:-}" ]]; then
  echo "TEST_UPDATE_VERSION and TEST_UPDATE_STATE are only for local app/run builds." >&2
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
  BUNDLE_IDENTIFIER="$bundle_identifier" \
  RELEASE_SUFFIX=developer-id

for artifact in "$release_zip" "$release_dmg" "$coverage_json" "$coverage_markdown"; do
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
gh release create "$tag" \
  "${release_zip}#md2png ${version} — macOS app archive (Apple silicon)" \
  "${release_dmg}#md2png ${version} — macOS installer (Apple silicon)" \
  "${latest_dmg}#md2png — latest macOS installer (Apple silicon)" \
  "${coverage_json}#md2png ${version} — normalized source-line coverage (JSON)" \
  "${coverage_markdown}#md2png ${version} — source-line coverage summary (Markdown)" \
  --repo "$repo_ref" \
  --title "md2png ${version}" \
  --notes-file "$notes_file" \
  --verify-tag \
  --latest \
  --fail-on-no-commits

uploaded_assets="$(
  gh release view "$tag" --repo "$repo_ref" --json assets --jq '.assets[].name'
)"
expected_assets=(
  "$(basename "$release_zip")"
  "$(basename "$release_dmg")"
  "$(basename "$latest_dmg")"
  "$(basename "$coverage_json")"
  "$(basename "$coverage_markdown")"
)
for expected_asset in "${expected_assets[@]}"; do
  if ! grep -Fxq "$expected_asset" <<< "$uploaded_assets"; then
    echo "Published release is missing asset: ${expected_asset}" >&2
    exit 1
  fi
done

versioned_dmg_name="$(basename "$release_dmg")"
release_endpoint="repos/${gh_repo}/releases/tags/${tag}"
versioned_dmg_count="$(
  gh api --hostname "$gh_host" "$release_endpoint" \
    --jq "[.assets[] | select(.name == \"${versioned_dmg_name}\")] | length"
)"
if [[ "$versioned_dmg_count" != "1" ]]; then
  echo "Published release must contain exactly one versioned DMG asset." >&2
  exit 1
fi

versioned_dmg_type="$(
  gh api --hostname "$gh_host" "$release_endpoint" \
    --jq ".assets[] | select(.name == \"${versioned_dmg_name}\") | .content_type"
)"
versioned_dmg_size="$(
  gh api --hostname "$gh_host" "$release_endpoint" \
    --jq ".assets[] | select(.name == \"${versioned_dmg_name}\") | .size"
)"
versioned_dmg_digest="$(
  gh api --hostname "$gh_host" "$release_endpoint" \
    --jq ".assets[] | select(.name == \"${versioned_dmg_name}\") | .digest"
)"
if [[ "$versioned_dmg_type" != "application/x-apple-diskimage" ]]; then
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
stable_dmg_url="${project_url}/releases/latest/download/$(basename "$latest_dmg")"
printf 'Release: %s\nLatest DMG: %s\n' "$release_url" "$stable_dmg_url"
