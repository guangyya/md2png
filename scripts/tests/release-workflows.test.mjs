import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const workflowDirectory = path.join(repoRoot, ".github/workflows");
const dependabotPath = path.join(repoRoot, ".github/dependabot.yml");
const workflowNames = ["prepare-release-pr.yml", "release-preflight.yml", "release.yml"];
const workflows = Object.fromEntries(workflowNames.map((name) => [
  name,
  fs.readFileSync(path.join(workflowDirectory, name), "utf8"),
]));
const allWorkflows = Object.fromEntries(fs.readdirSync(workflowDirectory)
  .filter((name) => /\.ya?ml$/.test(name))
  .sort()
  .map((name) => [name, fs.readFileSync(path.join(workflowDirectory, name), "utf8")]));

function parseYamlDocument(content) {
  const json = execFileSync("/usr/bin/ruby", [
    "-ryaml",
    "-rjson",
    "-e",
    String.raw`
content = STDIN.read
document = Psych.parse(content)
uses = []

collect_uses = lambda do |node, location|
  case node
  when Psych::Nodes::Mapping
    node.children.each_slice(2) do |key, value|
      key_name = key.is_a?(Psych::Nodes::Scalar) ? key.value : nil
      child_location = "#{location}.#{key_name || "?"}"
      if key_name == "uses"
        uses << {
          "location" => child_location,
          "reference" => value.is_a?(Psych::Nodes::Scalar) ? value.value : nil,
          "line" => value.start_line,
        }
      end
      collect_uses.call(value, child_location)
    end
  when Psych::Nodes::Sequence
    node.children.each_with_index do |child, index|
      collect_uses.call(child, "#{location}[#{index}]")
    end
  end
end

collect_uses.call(document.root, "$")
print JSON.generate({
  "value" => YAML.safe_load(content),
  "uses" => uses,
})
`,
  ], { encoding: "utf8", input: content });
  return JSON.parse(json);
}

function parseYaml(content) {
  return parseYamlDocument(content).value;
}

function hasVersionAnnotation(sourceLines, line) {
  return /\s+#\s*v\d+(?:\.\d+){0,2}\s*$/.test(sourceLines[line] ?? "");
}

function assertPinnedExternalActions(name, content) {
  const { uses } = parseYamlDocument(content);
  assert.ok(uses.length > 0, `${name} should use at least one reviewed action`);

  const sourceLines = content.split(/\r?\n/);
  for (const { line, location, reference } of uses) {
    assert.equal(typeof reference, "string", `${name}: ${location} must be a string`);
    if (reference.startsWith("./")) {
      continue;
    }
    assert.match(reference, /^[\w.-]+\/[\w.-]+(?:\/[\w./-]+)?@[0-9a-f]{40}$/, `${name}: ${reference}`);
    assert.ok(
      hasVersionAnnotation(sourceLines, line),
      `${name}: ${location} (${reference}) needs an exact same-line Dependabot version comment`,
    );
  }
}

test("all workflows pin every external action to a full commit", () => {
  for (const [name, content] of Object.entries(allWorkflows)) {
    assertPinnedExternalActions(name, content);
  }
});

test("action pinning cannot be bypassed with equivalent YAML syntax", () => {
  const bypasses = [
    "- uses: actions/checkout@v7 # this unpinned action must still be inspected",
    "- uses : actions/checkout@v7",
    "- { uses: actions/checkout@v7 }",
    "- { \"uses\": \"actions/checkout@v7\" }",
  ];
  for (const bypass of bypasses) {
    const fixture = `
steps:
  ${bypass}
  - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
`;
    assert.throws(
      () => assertPinnedExternalActions("equivalent-syntax.yml", fixture),
      /actions\/checkout@v7/,
      bypass,
    );
  }
});

test("action pinning accepts quoted and inline-map pinned references", () => {
  const fixture = `
steps:
  - uses : "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" # v7.0.1
  - { "uses": "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020" } # v7.0.0
`;
  assertPinnedExternalActions("quoted-pinned.yml", fixture);
});

test("action version comments must be on the parsed uses source line", () => {
  const fixture = `
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
  - run: 'echo "uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"' # v7.0.1
  - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
`;
  assert.throws(
    () => assertPinnedExternalActions("misplaced-comment.yml", fixture),
    /checkout.*needs an exact same-line Dependabot version comment/,
  );
});

test("Dependabot structurally configures weekly GitHub Actions updates", () => {
  const dependabot = parseYaml(fs.readFileSync(dependabotPath, "utf8"));
  assert.deepEqual(Object.keys(dependabot).sort(), ["updates", "version"]);
  assert.equal(dependabot.version, 2);
  assert.equal(dependabot.updates.length, 1);

  const update = dependabot.updates[0];
  assert.deepEqual(Object.keys(update).sort(), [
    "directory",
    "groups",
    "labels",
    "open-pull-requests-limit",
    "package-ecosystem",
    "schedule",
  ]);
  assert.equal(update["package-ecosystem"], "github-actions");
  assert.equal(update.directory, "/");
  assert.deepEqual(update.schedule, {
    interval: "weekly",
    day: "monday",
    time: "09:00",
    timezone: "Asia/Shanghai",
  });
  assert.equal(update["open-pull-requests-limit"], 5);
  assert.deepEqual(update.labels, ["technical-debt"]);
  assert.deepEqual(update.groups, {
    "github-actions": {
      "applies-to": "version-updates",
      patterns: ["*"],
    },
  });
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

test("published reruns use a protected-main read-only verifier", () => {
  const release = workflows["release.yml"];
  const verifyJob = release.slice(release.indexOf("  verify-published:"), release.indexOf("  validate:"));
  const verifier = fs.readFileSync(path.join(repoRoot, "scripts/verify-published-release.sh"), "utf8");

  assert.match(release, /already_published: \$\{\{ steps\.release\.outputs\.already_published \}\}/);
  assert.match(release, /"v\$\{version\}"\)[\s\S]*?already_published=true/);
  assert.match(release, /git cat-file -t "refs\/tags\/\$\{latest_tag\}"/);
  assert.match(release, /git rev-parse "refs\/tags\/\$\{latest_tag\}\^\{\}"\)" = "\$source_commit"/);
  assert.match(verifyJob, /already_published == 'true'/);
  assert.match(verifyJob, /permissions:\n      contents: read\n      issues: read/);
  assert.doesNotMatch(verifyJob, /contents: write|issues: write|environment: release-signing|secrets\./);
  assert.match(verifyJob, /WORKFLOW_REF: \$\{\{ github\.ref \}\}/);
  assert.match(verifyJob, /\[\[ "\$WORKFLOW_REF" != "refs\/heads\/main" \]\]/);
  assert.match(verifyJob, /git merge-base --is-ancestor "\$WORKFLOW_COMMIT" refs\/remotes\/origin\/main/);
  assert.match(verifyJob, /git merge-base --is-ancestor "\$SOURCE_COMMIT" "\$WORKFLOW_COMMIT"/);
  assert.match(verifyJob, /run: \.\/scripts\/verify-published-release\.sh/);
  assert.match(verifyJob, /EXPECTED_CERTIFICATE_SHA256: [0-9A-F]{64}/);
  assert.equal(
    [...release.matchAll(/if: needs\.detect\.outputs\.is_release == 'true' && needs\.detect\.outputs\.already_published != 'true'/g)].length,
    3,
  );

  assert.match(verifier, /gh release download/);
  assert.match(verifier, /remote_digest/);
  assert.match(verifier, /codesign --verify --deep --strict/);
  assert.match(verifier, /codesign -d --extract-certificates/);
  assert.match(verifier, /openssl x509[\s\S]*?-fingerprint[\s\S]*?-sha256/);
  assert.match(verifier, /actual_certificate_sha256" = "\$expected_certificate_sha256/);
  assert.match(verifier, /xcrun stapler validate/);
  assert.match(verifier, /spctl --assess --type execute/);
  assert.match(verifier, /issues\/42/);
  assert.doesNotMatch(verifier, /gh release (?:create|upload|edit)|--method (?:PATCH|POST|PUT|DELETE)|--clobber/);
});

test("trusted publication updates coverage history in the originating workflow", () => {
  const publisher = fs.readFileSync(path.join(repoRoot, "scripts/publish-hosted-release.sh"), "utf8");
  const release = workflows["release.yml"];
  assert.match(publisher, /scripts\/coverage-history\.mjs/);
  assert.match(publisher, /git merge-base --is-ancestor "\$source_commit" origin\/main/);
  assert.doesNotMatch(publisher, /--clobber|pull_request_target/);
  assert.match(release, /WORKFLOW_COMMIT: \$\{\{ github\.sha \}\}/);
  assert.match(release, /WORKFLOW_REF: \$\{\{ github\.ref \}\}/);
  assert.match(release, /\[\[ "\$WORKFLOW_REF" != "refs\/heads\/main" \]\]/);
  assert.match(release, /git fetch origin main:refs\/remotes\/origin\/main/);
  assert.match(release, /git merge-base --is-ancestor "\$WORKFLOW_COMMIT" refs\/remotes\/origin\/main/);
  assert.match(release, /git merge-base --is-ancestor "\$SOURCE_COMMIT" "\$WORKFLOW_COMMIT"/);
  assert.match(release, /git show "\$\{WORKFLOW_COMMIT\}:scripts\/publish-hosted-release\.sh"/);
  assert.match(release, /run: REPO_ROOT="\$GITHUB_WORKSPACE" "\$TRUSTED_PUBLISHER"/);
});

test("release remains draft until every uploaded asset has been verified", () => {
  const publisher = fs.readFileSync(path.join(repoRoot, "scripts/publish-hosted-release.sh"), "utf8");
  const resolveReleaseId = publisher.indexOf("--json databaseId");
  const releaseEndpoint = publisher.indexOf('release_endpoint="repos/${gh_repo}/releases/${release_id}"');
  const createDraft = publisher.indexOf("--draft");
  const upload = publisher.indexOf("gh release upload");
  const exactAssetSet = publisher.indexOf('if [[ "$published_names" != "$expected_names_text" ]]');
  const publish = publisher.indexOf('--draft=false --latest');

  assert.ok(resolveReleaseId >= 0, "draft Releases must be resolved through gh release view");
  assert.ok(releaseEndpoint > resolveReleaseId, "Release API reads must use the resolved database ID");
  assert.doesNotMatch(publisher, /releases\/tags\//);
  assert.ok(createDraft >= 0, "new releases must start as drafts");
  assert.ok(upload > createDraft, "assets must upload after draft creation");
  assert.ok(exactAssetSet > upload, "the complete asset set must be verified after upload");
  assert.ok(publish > exactAssetSet, "the draft must publish only after asset verification");
  assert.match(publisher, /Published Release is missing a verified asset/);
  assert.match(publisher, /published_release_json=.*"\$release_endpoint"/);
  assert.match(publisher, /\.draft <<< "\$published_release_json"\)" = "false"/);
});
