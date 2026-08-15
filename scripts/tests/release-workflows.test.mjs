import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const workflowDirectory = path.join(repoRoot, ".github/workflows");
const dependabot = fs.readFileSync(path.join(repoRoot, ".github/dependabot.yml"), "utf8");
const workflowNames = ["prepare-release-pr.yml", "release-preflight.yml", "release.yml"];
const workflows = Object.fromEntries(workflowNames.map((name) => [
  name,
  fs.readFileSync(path.join(workflowDirectory, name), "utf8"),
]));
const allWorkflows = Object.fromEntries(fs.readdirSync(workflowDirectory)
  .filter((name) => /\.ya?ml$/.test(name))
  .sort()
  .map((name) => [name, fs.readFileSync(path.join(workflowDirectory, name), "utf8")]));

test("all workflows pin every external action to a full commit", () => {
  for (const [name, content] of Object.entries(allWorkflows)) {
    const uses = [...content.matchAll(/^\s*uses:\s*([^\s#]+)(?:\s+#\s*(\S+))?\s*$/gm)];
    assert.ok(uses.length > 0, `${name} should use at least one reviewed action`);
    for (const [, reference, version] of uses) {
      assert.match(reference, /^[\w.-]+\/[\w.-]+@[0-9a-f]{40}$/, `${name}: ${reference}`);
      assert.match(version ?? "", /^v\d+(?:\.\d+){0,2}$/, `${name}: ${reference} needs a Dependabot version comment`);
    }
  }
});

test("Dependabot checks pinned GitHub Actions every week", () => {
  assert.match(dependabot, /package-ecosystem:\s*"github-actions"/);
  assert.match(dependabot, /directory:\s*"\/"/);
  assert.match(dependabot, /schedule:\n\s+interval:\s*"weekly"/);
  assert.match(dependabot, /day:\s*"monday"/);
  assert.match(dependabot, /timezone:\s*"Asia\/Shanghai"/);
  assert.match(dependabot, /actions-minor-patch:[\s\S]*?patterns:\n\s+- "\*"[\s\S]*?"minor"[\s\S]*?"patch"/);
  assert.match(dependabot, /actions-major:[\s\S]*?patterns:\n\s+- "\*"[\s\S]*?"major"/);
});

test("pull request code remains read-only and never uses pull_request_target", () => {
  const preflight = workflows["release-preflight.yml"];
  assert.doesNotMatch(preflight, /pull_request_target/);
  assert.match(preflight, /permissions:\n  contents: read\n  pull-requests: read/);
  assert.doesNotMatch(preflight, /secrets\./);
  assert.doesNotMatch(preflight, /contents: write|issues: write/);
});

test("coverage runs only in the trusted post-merge Release build", () => {
  const preflight = workflows["release-preflight.yml"];
  assert.match(preflight, /verify:\n[\s\S]*?if: needs\.detect\.outputs\.is_release == 'true'/);
  assert.doesNotMatch(preflight, /make coverage/);
  assert.doesNotMatch(workflows["prepare-release-pr.yml"], /make coverage/);
  assert.match(workflows["release.yml"], /make coverage SOURCE_COMMIT=/);
});

test("preparation App token has only branch and pull request write permissions", () => {
  const prepare = workflows["prepare-release-pr.yml"];
  assert.match(prepare, /permission-contents: write\n          permission-pull-requests: write/);
  assert.doesNotMatch(prepare, /permission-(actions|issues|workflows): write/);
  assert.match(prepare, /persist-credentials: false/);
});

test("Apple secrets and GitHub publication permissions are isolated", () => {
  const release = workflows["release.yml"];
  const sign = release.slice(release.indexOf("  sign:"), release.indexOf("  publish:"));
  const publish = release.slice(release.indexOf("  publish:"));
  assert.match(sign, /environment: release-signing/);
  assert.match(sign, /RELEASE_CERTIFICATE_P12_BASE64/);
  assert.match(sign, /openssl x509 -checkend 0/);
  assert.doesNotMatch(sign, /contents: write|issues: write/);
  assert.match(publish, /contents: write\n      issues: write/);
  assert.doesNotMatch(publish, /RELEASE_CERTIFICATE|APPLE_APP_SPECIFIC_PASSWORD|APPLE_ID/);
  assert.match(publish, /publish-hosted-release\.sh/);
});

test("release authorization checks the PR head and accepts only successful named gates", () => {
  const release = workflows["release.yml"];
  assert.match(release, /pr_head_sha="\$\(jq -r '\.\[0\]\.head\.sha'/);
  assert.match(release, /commits\/\$\{pr_head_sha\}\/check-runs\?per_page=100/);
  assert.doesNotMatch(release, /commits\/\$\{source_commit\}\/check-runs\?per_page=100/);
  assert.doesNotMatch(release, /gh pr checks/);
  assert.match(release, /CI \/ macOS 15 \/ Xcode 26\.2/);
  assert.match(release, /CI \/ macOS 26 \/ Xcode 26\.6/);
  assert.match(release, /Release preflight \/ Xcode 26\.2/);
  assert.doesNotMatch(release, /CI \/ Xcode 27 preview/);
  assert.match(release, /\[\[ "\$check_state" != "SUCCESS" \]\]/);
  assert.doesNotMatch(release, /SUCCESS\|SKIPPED|SUCCESS\|NEUTRAL|SKIPPED\|NEUTRAL/);
});

test("trusted publication updates coverage history in the originating workflow", () => {
  const publisher = fs.readFileSync(path.join(repoRoot, "scripts/publish-hosted-release.sh"), "utf8");
  assert.match(publisher, /scripts\/coverage-history\.mjs/);
  assert.match(publisher, /git merge-base --is-ancestor "\$source_commit" origin\/main/);
  assert.doesNotMatch(publisher, /--clobber|pull_request_target/);
});

test("release remains draft until every uploaded asset has been verified", () => {
  const publisher = fs.readFileSync(path.join(repoRoot, "scripts/publish-hosted-release.sh"), "utf8");
  const createDraft = publisher.indexOf("--draft");
  const upload = publisher.indexOf("gh release upload");
  const exactAssetSet = publisher.indexOf('if [[ "$published_names" != "$expected_names_text" ]]');
  const publish = publisher.indexOf('--draft=false --latest');

  assert.ok(createDraft >= 0, "new releases must start as drafts");
  assert.ok(upload > createDraft, "assets must upload after draft creation");
  assert.ok(exactAssetSet > upload, "the complete asset set must be verified after upload");
  assert.ok(publish > exactAssetSet, "the draft must publish only after asset verification");
  assert.match(publisher, /Published Release is missing a verified asset/);
  assert.match(publisher, /published_release_json=.*releases\/tags\/\$\{tag\}/);
  assert.match(publisher, /\.draft <<< "\$published_release_json"\)" = "false"/);
});
