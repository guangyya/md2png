#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

node_binary="${NODE:-node}"
gh_host="${GH_HOST:-github.com}"
gh_repo="${GH_REPO:-}"
handoff_dir="${RELEASE_HANDOFF_DIR:-}"
source_commit="${SOURCE_COMMIT:-}"
project_url="${PROJECT_URL:-}"
bundle_identifier="${BUNDLE_IDENTIFIER:-}"

if [[ ! "$gh_repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GH_REPO is required in OWNER/REPOSITORY form." >&2
  exit 1
fi
if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "SOURCE_COMMIT must be a full lowercase commit SHA." >&2
  exit 1
fi
if [[ ! -d "$handoff_dir" ]]; then
  echo "RELEASE_HANDOFF_DIR must name the downloaded handoff directory." >&2
  exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$source_commit" ]]; then
  echo "The publication checkout does not match SOURCE_COMMIT." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "The trusted publication checkout must be clean." >&2
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
tag="v${version}"
release_zip_name="md2png-${version}-macOS-arm64-developer-id.zip"
release_dmg_name="md2png-${version}-macOS-arm64-developer-id.dmg"
latest_dmg_name="md2png-latest.dmg"
coverage_json_name="md2png-${version}-coverage.json"
coverage_markdown_name="md2png-${version}-coverage.md"
manifest_path="${handoff_dir}/release-manifest.json"
notes_file="$RUNNER_TEMP/release-notes-${version}.md"

"$node_binary" scripts/release-manifest.mjs validate \
  --manifest "$manifest_path" \
  --directory "$handoff_dir" \
  --version "$version" \
  --build "$build_number" \
  --commit "$source_commit" >/dev/null
"$node_binary" scripts/coverage-report.mjs validate \
  --report "${handoff_dir}/${coverage_json_name}" \
  --app-version "$version" \
  --commit "$source_commit"

if ! cmp -s "${handoff_dir}/${release_dmg_name}" "${handoff_dir}/${latest_dmg_name}"; then
  echo "The latest DMG alias differs from the versioned DMG." >&2
  exit 1
fi

mkdir -p "$(dirname "$notes_file")"
./scripts/release-notes.sh "$version" CHANGELOG.md > "$notes_file"
if [[ ! -s "$notes_file" ]]; then
  echo "Release notes are empty for $version." >&2
  exit 1
fi

verify_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$verify_dir"
}
trap cleanup EXIT
ditto -x -k "${handoff_dir}/${release_zip_name}" "$verify_dir"
app_path="$(find "$verify_dir" -maxdepth 2 -type d -name md2png.app -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "The signed ZIP does not contain md2png.app." >&2
  exit 1
fi
app_plist="${app_path}/Contents/Info.plist"
executable="${app_path}/Contents/MacOS/md2png"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_plist")" = "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_plist")" = "$build_number"
test "$(/usr/libexec/PlistBuddy -c 'Print :MD2PNGSourceCommit' "$app_plist")" = "$source_commit"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_plist")" = "$bundle_identifier"
test "$(/usr/libexec/PlistBuddy -c 'Print :MD2PNGProjectURL' "$app_plist")" = "$project_url"
test "$(lipo -archs "$executable")" = "arm64"
codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
xcrun stapler validate "${handoff_dir}/${release_dmg_name}"
hdiutil verify "${handoff_dir}/${release_dmg_name}"
spctl --assess --type execute --verbose=2 "$app_path"
spctl --assess --type open --context context:primary-signature --verbose=2 \
  "${handoff_dir}/${release_dmg_name}"

git fetch origin main --tags
git merge-base --is-ancestor "$source_commit" origin/main
remote_tag_object="$(git ls-remote origin "refs/tags/${tag}" | awk '{print $1}')"
remote_tag_commit="$(git ls-remote origin "refs/tags/${tag}^{}" | awk '{print $1}')"
if [[ -n "$remote_tag_object" && -z "$remote_tag_commit" ]]; then
  echo "Existing tag $tag is lightweight; release tags must be annotated." >&2
  exit 1
fi
if [[ -n "$remote_tag_commit" && "$remote_tag_commit" != "$source_commit" ]]; then
  echo "Existing tag $tag points to $remote_tag_commit instead of $source_commit." >&2
  exit 1
fi
if [[ -z "$remote_tag_object" ]]; then
  git tag -a "$tag" "$source_commit" -m "md2png $version"
  git push origin "refs/tags/${tag}"
fi

repo_ref="${gh_host}/${gh_repo}"
release_exists=false
if gh release view "$tag" --repo "$repo_ref" >/dev/null 2>&1; then
  release_exists=true
fi
if [[ "$release_exists" = false ]]; then
  gh release create "$tag" \
    --repo "$repo_ref" \
    --title "md2png $version" \
    --notes-file "$notes_file" \
    --verify-tag \
    --latest
else
  release_json="$(gh api --hostname "$gh_host" "repos/${gh_repo}/releases/tags/${tag}")"
  test "$(jq -r .name <<< "$release_json")" = "md2png $version"
  test "$(jq -r .draft <<< "$release_json")" = "false"
  test "$(jq -r .prerelease <<< "$release_json")" = "false"
  expected_notes="$(cat "$notes_file")"
  actual_notes="$(jq -r .body <<< "$release_json")"
  if [[ "$actual_notes" != "$expected_notes" ]]; then
    echo "Existing Release notes do not match the committed changelog." >&2
    exit 1
  fi
fi

asset_label() {
  case "$1" in
    "$release_zip_name") printf 'md2png %s — macOS app archive (Apple silicon)' "$version" ;;
    "$release_dmg_name") printf 'md2png %s — macOS installer (Apple silicon)' "$version" ;;
    "$latest_dmg_name") printf 'md2png — latest macOS installer (Apple silicon)' ;;
    "$coverage_json_name") printf 'md2png %s — normalized source-line coverage (JSON)' "$version" ;;
    "$coverage_markdown_name") printf 'md2png %s — source-line coverage summary (Markdown)' "$version" ;;
    *) return 1 ;;
  esac
}

asset_content_type() {
  case "$1" in
    "$release_zip_name") printf 'application/zip' ;;
    "$release_dmg_name"|"$latest_dmg_name") printf 'application/x-apple-diskimage' ;;
    "$coverage_json_name") printf 'application/json' ;;
    "$coverage_markdown_name") printf 'application/octet-stream' ;;
    *) return 1 ;;
  esac
}

expected_names=(
  "$release_zip_name"
  "$release_dmg_name"
  "$latest_dmg_name"
  "$coverage_json_name"
  "$coverage_markdown_name"
)
for name in "${expected_names[@]}"; do
  local_path="${handoff_dir}/${name}"
  local_size="$(stat -f %z "$local_path")"
  local_digest="sha256:$(shasum -a 256 "$local_path" | awk '{print $1}')"
  asset_json="$(gh api --hostname "$gh_host" "repos/${gh_repo}/releases/tags/${tag}" \
    --jq ".assets[] | select(.name == \"${name}\")")"
  if [[ -z "$asset_json" ]]; then
    label="$(asset_label "$name")"
    gh release upload "$tag" "${local_path}#${label}" --repo "$repo_ref"
    asset_json="$(gh api --hostname "$gh_host" "repos/${gh_repo}/releases/tags/${tag}" \
      --jq ".assets[] | select(.name == \"${name}\")")"
  fi
  remote_count="$(gh api --hostname "$gh_host" "repos/${gh_repo}/releases/tags/${tag}" \
    --jq "[.assets[] | select(.name == \"${name}\")] | length")"
  test "$remote_count" = "1"
  remote_size="$(jq -r .size <<< "$asset_json")"
  remote_digest="$(jq -r .digest <<< "$asset_json")"
  remote_content_type="$(jq -r .content_type <<< "$asset_json")"
  expected_content_type="$(asset_content_type "$name")"
  if [[ "$remote_size" != "$local_size" \
    || "$remote_digest" != "$local_digest" \
    || "$remote_content_type" != "$expected_content_type" ]]; then
    echo "Published asset differs from the verified handoff: $name" >&2
    exit 1
  fi
done

published_names="$(gh api --hostname "$gh_host" "repos/${gh_repo}/releases/tags/${tag}" --jq '.assets[].name' | LC_ALL=C sort)"
expected_names_text="$(printf '%s\n' "${expected_names[@]}" | LC_ALL=C sort)"
if [[ "$published_names" != "$expected_names_text" ]]; then
  echo "Published Release has unexpected or missing assets." >&2
  diff -u <(printf '%s\n' "$expected_names_text") <(printf '%s\n' "$published_names") >&2 || true
  exit 1
fi

gh release edit "$tag" --repo "$repo_ref" --latest
latest_tag="$(gh api --hostname "$gh_host" "repos/${gh_repo}/releases/latest" --jq .tag_name)"
test "$latest_tag" = "$tag"

GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN is required}" \
  "$node_binary" scripts/coverage-history.mjs

release_url="$(gh release view "$tag" --repo "$repo_ref" --json url --jq .url)"
printf 'Release: %s\nSource: %s\n' "$release_url" "$source_commit"
