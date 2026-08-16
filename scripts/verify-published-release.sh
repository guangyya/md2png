#!/bin/bash
set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$repo_root"

node_binary="${NODE:-node}"
release_assets_script="${RELEASE_ASSETS_SCRIPT:-scripts/release-assets.mjs}"
gh_host="${GH_HOST:-github.com}"
gh_repo="${GH_REPO:-}"
source_commit="${SOURCE_COMMIT:-}"
expected_version="${EXPECTED_VERSION:-}"
expected_build="${EXPECTED_BUILD:-}"
expected_certificate_sha256="${EXPECTED_CERTIFICATE_SHA256:-}"
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
if [[ ! "$expected_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "EXPECTED_VERSION must be a stable semantic version." >&2
  exit 1
fi
if [[ ! "$expected_build" =~ ^[1-9][0-9]*$ ]]; then
  echo "EXPECTED_BUILD must be a positive integer." >&2
  exit 1
fi
if [[ ! "$expected_certificate_sha256" =~ ^[0-9A-F]{64}$ ]]; then
  echo "EXPECTED_CERTIFICATE_SHA256 must be an uppercase SHA-256 fingerprint." >&2
  exit 1
fi
if [[ "$project_url" != "https://${gh_host}/${gh_repo}" ]]; then
  echo "PROJECT_URL must identify GH_REPO on GH_HOST." >&2
  exit 1
fi
if [[ -z "$bundle_identifier" ]]; then
  echo "BUNDLE_IDENTIFIER is required." >&2
  exit 1
fi

git cat-file -e "${source_commit}^{commit}"
git merge-base --is-ancestor "$source_commit" refs/remotes/origin/main

verify_dir="$(mktemp -d)"
mounted_dmg=false
cleanup() {
  if [[ "$mounted_dmg" = "true" ]]; then
    hdiutil detach "$verify_dir/dmg" >/dev/null 2>&1 || true
  fi
  rm -rf "$verify_dir"
}
trap cleanup EXIT

source_plist="$verify_dir/source-Info.plist"
source_changelog="$verify_dir/source-CHANGELOG.md"
notes_file="$verify_dir/release-notes.md"
git show "${source_commit}:Info.plist" > "$source_plist"
git show "${source_commit}:CHANGELOG.md" > "$source_changelog"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$source_plist")"
test "$version" = "$expected_version"
test "$build_number" = "$expected_build"
tag="v${version}"

test "$(git cat-file -t "refs/tags/${tag}")" = "tag"
test "$(git rev-parse "refs/tags/${tag}^{}")" = "$source_commit"

repo_ref="${gh_host}/${gh_repo}"
release_id="$(gh release view "$tag" \
  --repo "$repo_ref" \
  --json databaseId \
  --jq .databaseId)"
if [[ ! "$release_id" =~ ^[0-9]+$ ]]; then
  echo "Cannot resolve the GitHub Release ID for $tag." >&2
  exit 1
fi
release_endpoint="repos/${gh_repo}/releases/${release_id}"
release_json="$(gh api --hostname "$gh_host" "$release_endpoint")"
test "$(jq -r .tag_name <<< "$release_json")" = "$tag"
test "$(jq -r .name <<< "$release_json")" = "md2png $version"
test "$(jq -r .draft <<< "$release_json")" = "false"
test "$(jq -r .prerelease <<< "$release_json")" = "false"
test "$(jq -r .published_at <<< "$release_json")" != "null"
test "$(gh api --hostname "$gh_host" "repos/${gh_repo}/releases/latest" --jq .id)" = "$release_id"

./scripts/release-notes.sh "$version" "$source_changelog" > "$notes_file"
test -s "$notes_file"
expected_notes="$(cat "$notes_file")"
actual_notes="$(jq -r .body <<< "$release_json")"
test "$actual_notes" = "$expected_notes"

asset_contract_json="$("$node_binary" "$release_assets_script" json --version "$version")"
asset_value_by_key() {
  jq -er --arg key "$1" --arg field "$2" \
    '.assets[] | select(.key == $key) | .[$field]' <<< "$asset_contract_json"
}
asset_value_by_name() {
  jq -er --arg name "$1" --arg field "$2" \
    '.assets[] | select(.name == $name) | .[$field]' <<< "$asset_contract_json"
}
release_zip_name="$(asset_value_by_key releaseZip name)"
appcast_name="$(jq -r '.assets[] | select(.key == "appcast") | .name' <<< "$asset_contract_json")"
release_dmg_name="$(asset_value_by_key releaseDmg name)"
latest_dmg_name="$(asset_value_by_key latestDmg name)"
coverage_json_name="$(asset_value_by_key coverageJson name)"
coverage_markdown_name="$(asset_value_by_key coverageMarkdown name)"
expected_names=()
while IFS= read -r name; do
  expected_names+=("$name")
done < <(jq -r '.assets[].name' <<< "$asset_contract_json")

assets_dir="$verify_dir/assets"
mkdir -p "$assets_dir"
gh release download "$tag" --repo "$repo_ref" --dir "$assets_dir"

published_names="$(jq -r '.assets[].name' <<< "$release_json" | LC_ALL=C sort)"
expected_names_text="$(printf '%s\n' "${expected_names[@]}" | LC_ALL=C sort)"
if [[ "$published_names" != "$expected_names_text" ]]; then
  echo "Published Release has unexpected or missing assets." >&2
  exit 1
fi

for name in "${expected_names[@]}"; do
  asset_count="$(jq --arg name "$name" '[.assets[] | select(.name == $name)] | length' <<< "$release_json")"
  test "$asset_count" = "1"
  asset_json="$(jq -c --arg name "$name" '.assets[] | select(.name == $name)' <<< "$release_json")"
  local_path="${assets_dir}/${name}"
  test -f "$local_path"
  remote_size="$(jq -r .size <<< "$asset_json")"
  remote_digest="$(jq -r .digest <<< "$asset_json")"
  remote_content_type="$(jq -r .content_type <<< "$asset_json")"
  remote_label="$(jq -r .label <<< "$asset_json")"
  test "$(jq -r .state <<< "$asset_json")" = "uploaded"
  [[ "$remote_size" =~ ^[1-9][0-9]*$ ]]
  test "$(stat -f %z "$local_path")" = "$remote_size"
  test "sha256:$(shasum -a 256 "$local_path" | awk '{print $1}')" = "$remote_digest"
  test "$remote_content_type" = "$(asset_value_by_name "$name" contentType)"
  test "$remote_label" = "$(asset_value_by_name "$name" label)"
done

if [[ -n "$appcast_name" ]]; then
  "$node_binary" scripts/sparkle-appcast.mjs validate \
    --file "${assets_dir}/${appcast_name}" \
    --archive "${assets_dir}/${release_zip_name}" \
    --version "$version" \
    --build "$build_number" \
    --repository "$gh_repo" \
    --public-key "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$source_plist")"
fi

cmp -s "${assets_dir}/${release_dmg_name}" "${assets_dir}/${latest_dmg_name}"
"$node_binary" scripts/coverage-report.mjs validate \
  --report "${assets_dir}/${coverage_json_name}" \
  --app-version "$version" \
  --commit "$source_commit"
"$node_binary" --input-type=module -e '
  import fs from "node:fs";
  import { coverageMarkdown } from "./scripts/coverage-report.mjs";
  const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const markdown = fs.readFileSync(process.argv[2], "utf8");
  if (markdown !== coverageMarkdown(report)) {
    throw new Error("published coverage Markdown does not match its JSON source");
  }
' "${assets_dir}/${coverage_json_name}" "${assets_dir}/${coverage_markdown_name}"

app_dir="$verify_dir/app"
mkdir -p "$app_dir"
ditto -x -k "${assets_dir}/${release_zip_name}" "$app_dir"
app_count="$(find "$app_dir" -maxdepth 2 -type d -name md2png.app | wc -l | tr -d ' ')"
test "$app_count" = "1"
app_path="$(find "$app_dir" -maxdepth 2 -type d -name md2png.app -print -quit)"

verify_signer() {
  local candidate="$1"
  local package_name="$2"
  local certificate_dir="$verify_dir/certificate-${package_name}"
  local actual_certificate_sha256
  mkdir -p "$certificate_dir"
  (
    cd "$certificate_dir"
    codesign -d --extract-certificates "$candidate" >/dev/null 2>&1
  )
  actual_certificate_sha256="$(openssl x509 \
    -inform DER \
    -in "$certificate_dir/codesign0" \
    -noout \
    -fingerprint \
    -sha256 |
    cut -d= -f2 |
    tr -d ':' |
    tr '[:lower:]' '[:upper:]')"
  test "$actual_certificate_sha256" = "$expected_certificate_sha256"
}

verify_app() {
  local candidate="$1"
  local package_name="$2"
  local candidate_plist="${candidate}/Contents/Info.plist"
  local candidate_executable="${candidate}/Contents/MacOS/md2png"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate_plist")" = "$version"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$candidate_plist")" = "$build_number"
  test "$(/usr/libexec/PlistBuddy -c 'Print :MD2PNGSourceCommit' "$candidate_plist")" = "$source_commit"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate_plist")" = "$bundle_identifier"
  test "$(/usr/libexec/PlistBuddy -c 'Print :MD2PNGProjectURL' "$candidate_plist")" = "$project_url"
  test "$(lipo -archs "$candidate_executable")" = "arm64"
  codesign --verify --deep --strict --verbose=2 "$candidate"
  verify_signer "$candidate" "$package_name"
  xcrun stapler validate "$candidate"
  spctl --assess --type execute --verbose=2 "$candidate" 2>&1 |
    sed -E 's/origin=.*/origin=<redacted>/'
  /usr/bin/env -u GH_TOKEN -u GITHUB_TOKEN "$candidate_executable" --self-test
}

verify_app "$app_path" zip
codesign --verify --strict --verbose=2 "${assets_dir}/${release_dmg_name}"
verify_signer "${assets_dir}/${release_dmg_name}" dmg-container
xcrun stapler validate "${assets_dir}/${release_dmg_name}"
hdiutil verify "${assets_dir}/${release_dmg_name}"
spctl --assess --type open --context context:primary-signature --verbose=2 \
  "${assets_dir}/${release_dmg_name}" 2>&1 |
  sed -E 's/origin=.*/origin=<redacted>/'

mkdir -p "$verify_dir/dmg"
hdiutil attach -nobrowse -readonly -mountpoint "$verify_dir/dmg" \
  "${assets_dir}/${release_dmg_name}" >/dev/null
mounted_dmg=true
dmg_entries="$(find "$verify_dir/dmg" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
test "$dmg_entries" = $'Applications\nmd2png.app'
test -L "$verify_dir/dmg/Applications"
test "$(readlink "$verify_dir/dmg/Applications")" = "/Applications"
mounted_app_count="$(find "$verify_dir/dmg" -maxdepth 2 -type d -name md2png.app | wc -l | tr -d ' ')"
test "$mounted_app_count" = "1"
mounted_app="$(find "$verify_dir/dmg" -maxdepth 2 -type d -name md2png.app -print -quit)"
verify_app "$mounted_app" dmg-app
diff -rq "$app_path" "$mounted_app"
hdiutil detach "$verify_dir/dmg" >/dev/null
mounted_dmg=false

coverage_issue="$(gh api --hostname "$gh_host" "repos/${gh_repo}/issues/42")"
test "$(jq -r .number <<< "$coverage_issue")" = "42"
test "$(jq 'has("pull_request")' <<< "$coverage_issue")" = "false"
coverage_body="$(jq -r .body <<< "$coverage_issue")"
release_link="${project_url}/releases/tag/${tag}"
commit_link="${project_url}/commit/${source_commit}"
test "$(grep -oF "$release_link" <<< "$coverage_body" | wc -l | tr -d ' ')" = "1"
test "$(grep -oF "$commit_link" <<< "$coverage_body" | wc -l | tr -d ' ')" = "1"

printf 'Verified published Release %s at %s without mutation.\n' "$tag" "$source_commit"
