import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
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
  assert.deepEqual(parseYaml(preflight).permissions, {
    contents: "read",
    issues: "read",
    "pull-requests": "read",
  });
  assert.doesNotMatch(preflight, /secrets\./);
  assert.doesNotMatch(preflight, /contents: write|issues: write/);
});

test("generated Release PR labels are verified from the live API with exact identity", () => {
  const prepareWorkflow = parseYaml(workflows["prepare-release-pr.yml"]);
  const preflightWorkflow = parseYaml(workflows["release-preflight.yml"]);
  const prepare = prepareWorkflow.jobs.prepare.steps.find(
    (step) => step.name === "Create focused release branch and pull request",
  );
  const preflight = preflightWorkflow.jobs.detect.steps.find(
    (step) => step.name === "Validate release metadata change",
  );

  assert.equal(preflight.env.PR_NUMBER, "${{ github.event.pull_request.number }}");
  assert.equal(Object.hasOwn(preflight.env, "PR_LABELS"), false);
  assert.ok(preflight.run.indexOf("release-pr-labels.mjs verify") > preflight.run.indexOf("validate-prepared"));
  assert.match(preflight.run, /--pull-request "\$PR_NUMBER"/);
  assert.match(preflight.run, /--head-sha "\$HEAD_SHA"/);
  assert.match(preflight.run, /--head-ref "\$HEAD_REF"/);
  assert.match(preflight.run, /--version "\$version"/);
  assert.match(preflight.run, /--bump "\$bump"/);

  const createIndex = prepare.run.indexOf("gh pr create");
  const verifyIndex = prepare.run.indexOf("release-pr-labels.mjs verify");
  assert.ok(createIndex >= 0 && verifyIndex > createIndex);
  assert.match(prepare.run, /GITHUB_TOKEN="\$APP_TOKEN" node scripts\/release-pr-labels\.mjs verify/);
  assert.match(prepare.run, /--pull-request "\$pr_number"/);
  assert.match(prepare.run, /--head-sha "\$\(git rev-parse HEAD\)"/);
});

test("coverage runs only in the trusted post-merge Release build", () => {
  const preflight = workflows["release-preflight.yml"];
  assert.match(preflight, /verify:\n[\s\S]*?if: needs\.detect\.outputs\.is_release == 'true'/);
  assert.doesNotMatch(preflight, /make coverage/);
  assert.doesNotMatch(workflows["prepare-release-pr.yml"], /make coverage/);
  assert.match(workflows["release.yml"], /make coverage SOURCE_COMMIT=/);
});

test("validate and sign stage trusted asset tooling before consuming it", () => {
  const releaseWorkflow = parseYaml(workflows["release.yml"]);
  const jobs = releaseWorkflow.jobs;
  for (const jobName of ["validate", "sign"]) {
    const job = jobs[jobName];
    const stageIndex = job.steps.findIndex((step) => step.name === "Stage trusted release asset tooling");
    assert.ok(stageIndex > 0, `${jobName} must stage tooling after checkout`);
    const stage = job.steps[stageIndex];
    assert.deepEqual(stage.env, {
      WORKFLOW_COMMIT: "${{ github.sha }}",
      WORKFLOW_REF: "${{ github.ref }}",
    });
    assert.match(stage.run, /\[\[ "\$WORKFLOW_REF" != "refs\/heads\/main" \]\]/);
    assert.match(stage.run, /git fetch origin main:refs\/remotes\/origin\/main/);
    assert.match(stage.run, /git merge-base --is-ancestor "\$WORKFLOW_COMMIT" refs\/remotes\/origin\/main/);
    assert.match(stage.run, /git merge-base --is-ancestor "\$SOURCE_COMMIT" "\$WORKFLOW_COMMIT"/);
    assert.match(stage.run, /for file in release-assets\.mjs release-assets\.json release-manifest\.mjs/);
    assert.match(stage.run, /git show "\$\{WORKFLOW_COMMIT\}:scripts\/\$\{file\}" > "\$trusted_dir\/\$file"/);
    const consumerIndex = job.steps.findIndex((step) => step.run?.includes("$RELEASE_ASSETS_SCRIPT"));
    assert.ok(consumerIndex > stageIndex, `${jobName} must consume only the previously staged helper`);
  }
  const signAssembly = jobs.sign.steps.find((step) => step.name === "Import, verify, sign, notarize, and assemble handoff");
  assert.match(signAssembly.run, /node "\$RELEASE_MANIFEST_SCRIPT" create/);
  const signStage = jobs.sign.steps.find((step) => step.name === "Stage trusted release asset tooling");
  assert.match(signStage.run, /release-recovery\.mjs/);
  assert.match(signStage.run, /RELEASE_RECOVERY_SCRIPT/);
});

test("partial-draft recovery reuses one trusted prior signed handoff", () => {
  const releaseWorkflow = parseYaml(workflows["release.yml"]);
  const jobs = releaseWorkflow.jobs;
  const detect = jobs.detect.steps.find((step) => step.name === "Validate release authorization");
  const sign = jobs.sign;
  const resolve = sign.steps.find((step) => step.name === "Resolve exact prior signed handoff");
  const download = sign.steps.find((step) => step.name === "Download exact prior signed handoff");
  const validate = sign.steps.find((step) => step.name === "Validate recovered signed handoff identity and digests");
  const freshStepNames = [
    "Install pinned renderer dependencies",
    "Download verified coverage",
    "Import, verify, sign, notarize, and assemble handoff",
  ];

  assert.equal(detect.env.REQUESTED_HANDOFF_RUN_ID, "${{ inputs.handoff_run_id }}");
  assert.equal(jobs.detect.outputs.recovery_handoff_run_id, "${{ steps.release.outputs.recovery_handoff_run_id }}");
  assert.match(detect.run, /releases\?per_page=100/);
  assert.match(detect.run, /select\(\.draft == true and \.tag_name == \$tag\)/);
  assert.match(detect.run, /draft_asset_count/);
  assert.match(detect.run, /Re-run failed jobs/);
  assert.match(detect.run, /handoff_run_id is accepted only when the existing draft already has assets/);

  assert.equal(sign.env.RECOVERY_HANDOFF_RUN_ID, "${{ needs.detect.outputs.recovery_handoff_run_id }}");
  for (const name of freshStepNames) {
    assert.equal(sign.steps.find((step) => step.name === name).if, "needs.detect.outputs.recovery_handoff_run_id == ''");
  }
  assert.equal(resolve.if, "needs.detect.outputs.recovery_handoff_run_id != ''");
  assert.equal(resolve.env.GITHUB_TOKEN, "${{ github.token }}");
  assert.equal(resolve.env.WORKFLOW_COMMIT, "${{ github.sha }}");
  assert.match(resolve.run, /release-recovery\.mjs|\$RELEASE_RECOVERY_SCRIPT/);
  assert.match(resolve.run, /--current-run "\$GITHUB_RUN_ID"/);
  assert.match(resolve.run, /--prior-run "\$RECOVERY_HANDOFF_RUN_ID"/);
  assert.match(resolve.run, /--source-commit "\$SOURCE_COMMIT"/);
  assert.match(resolve.run, /--workflow-commit "\$WORKFLOW_COMMIT"/);
  assert.match(resolve.run, /git merge-base --is-ancestor "\$SOURCE_COMMIT" "\$prior_workflow_commit"/);
  assert.match(resolve.run, /git merge-base --is-ancestor "\$prior_workflow_commit" "\$WORKFLOW_COMMIT"/);

  assert.equal(download.if, "needs.detect.outputs.recovery_handoff_run_id != ''");
  assert.equal(download.with["artifact-ids"], "${{ steps.recovery-handoff.outputs.artifact_id }}");
  assert.equal(download.with["run-id"], "${{ needs.detect.outputs.recovery_handoff_run_id }}");
  assert.equal(download.with.repository, "${{ github.repository }}");
  assert.equal(download.with["github-token"], "${{ github.token }}");
  assert.equal(download.with["merge-multiple"], true);
  assert.equal(validate.if, "needs.detect.outputs.recovery_handoff_run_id != ''");
  assert.match(validate.run, /release-manifest\.json/);
  assert.match(validate.run, /--version "\$VERSION"/);
  assert.match(validate.run, /--build "\$BUILD"/);
  assert.match(validate.run, /--commit "\$SOURCE_COMMIT"/);

  const upload = sign.steps.find((step) => step.name === "Upload verified signed handoff");
  assert.equal(Object.hasOwn(upload, "if"), false);
  assert.equal(upload.with.name, "signed-release-${{ needs.detect.outputs.source_commit }}");
});

test("trusted publication tooling can stage from main while a pre-contract source is checked out", (context) => {
  const releaseWorkflow = parseYaml(workflows["release.yml"]);
  const stage = releaseWorkflow.jobs.publish.steps.find(
    (step) => step.name === "Stage trusted publication implementation",
  );
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), "md2png-historical-recovery-"));
  const runnerTemp = fs.mkdtempSync(path.join(os.tmpdir(), "md2png-trusted-tooling-"));
  context.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  context.after(() => fs.rmSync(runnerTemp, { recursive: true, force: true }));
  const git = (...args) => execFileSync("git", args, { cwd: fixture, encoding: "utf8" }).trim();
  git("init", "-b", "main");
  git("config", "user.name", "Release Test");
  git("config", "user.email", "release-test@example.invalid");
  fs.writeFileSync(path.join(fixture, "README.md"), "historical source without asset tooling\n");
  git("add", "README.md");
  git("commit", "-m", "Historical source");
  const sourceCommit = git("rev-parse", "HEAD");
  fs.mkdirSync(path.join(fixture, "scripts"));
  for (const file of [
    "publish-hosted-release.sh",
    "release-assets.mjs",
    "release-assets.json",
    "release-manifest.mjs",
    "release-milestone.mjs",
  ]) {
    fs.copyFileSync(path.join(repoRoot, "scripts", file), path.join(fixture, "scripts", file));
  }
  git("add", "scripts");
  git("commit", "-m", "Add trusted asset tooling");
  const workflowCommit = git("rev-parse", "HEAD");
  git("remote", "add", "origin", fixture);
  git("checkout", "--detach", sourceCommit);
  assert.equal(fs.existsSync(path.join(fixture, "scripts/release-assets.mjs")), false);
  assert.equal(fs.existsSync(path.join(fixture, "scripts/release-milestone.mjs")), false);

  const githubEnv = path.join(runnerTemp, "github-env");
  const result = spawnSync("/bin/bash", ["-c", stage.run], {
    cwd: fixture,
    encoding: "utf8",
    env: {
      ...process.env,
      GITHUB_ENV: githubEnv,
      RUNNER_TEMP: runnerTemp,
      SOURCE_COMMIT: sourceCommit,
      WORKFLOW_COMMIT: workflowCommit,
      WORKFLOW_REF: "refs/heads/main",
    },
  });
  assert.equal(result.status, 0, result.stderr);
  const staged = Object.fromEntries(fs.readFileSync(githubEnv, "utf8").trim().split("\n")
    .map((line) => line.split(/=(.*)/s).slice(0, 2)));
  assert.ok(fs.existsSync(staged.RELEASE_ASSETS_SCRIPT));
  assert.ok(fs.existsSync(staged.RELEASE_MANIFEST_SCRIPT));
  assert.ok(fs.existsSync(staged.RELEASE_MILESTONE_SCRIPT));
  const rendered = spawnSync(process.execPath, [
    staged.RELEASE_ASSETS_SCRIPT,
    "names",
    "--version",
    "0.4.0",
  ], { encoding: "utf8" });
  assert.equal(rendered.status, 0, rendered.stderr);
  assert.equal(rendered.stdout.trim().split("\n").length, 5, rendered.stdout);
  const milestoneInvocation = spawnSync(process.execPath, [staged.RELEASE_MILESTONE_SCRIPT, "invalid"], {
    encoding: "utf8",
  });
  assert.equal(milestoneInvocation.status, 1, milestoneInvocation.stderr);
  assert.match(milestoneInvocation.stderr, /command must be plan or sync/);
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
  const releaseWorkflow = parseYaml(release);
  const releaseJobs = releaseWorkflow.jobs;
  const verifyJob = release.slice(release.indexOf("  verify-published:"), release.indexOf("  validate:"));
  const verifier = fs.readFileSync(path.join(repoRoot, "scripts/verify-published-release.sh"), "utf8");

  assert.match(release, /already_published: \$\{\{ steps\.release\.outputs\.already_published \}\}/);
  assert.deepEqual(releaseWorkflow.permissions, {
    checks: "read",
    contents: "read",
    "pull-requests": "read",
  });
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
  assert.equal(releaseJobs["verify-published"].if, "needs.detect.outputs.is_release == 'true' && needs.detect.outputs.already_published == 'true'");
  assert.equal(releaseJobs["verify-published"].needs, "detect");
  assert.deepEqual(releaseJobs["verify-published"].permissions, { contents: "read", issues: "read" });
  assert.equal(Object.hasOwn(releaseJobs["verify-published"], "environment"), false);
  const verifyCheckout = releaseJobs["verify-published"].steps.find((step) => step.name === "Check out trusted verification implementation");
  assert.equal(verifyCheckout.uses, "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1");
  assert.equal(verifyCheckout.with.ref, "${{ github.sha }}");
  assert.equal(verifyCheckout.with["fetch-depth"], 0);
  assert.equal(verifyCheckout.with["persist-credentials"], false);
  const mutationGuard = "needs.detect.outputs.is_release == 'true' && needs.detect.outputs.already_published != 'true'";
  for (const jobName of ["validate", "sign", "publish"]) {
    assert.equal(releaseJobs[jobName].if, mutationGuard, `${jobName} must be excluded from published no-op reruns`);
  }
  const writeJobs = [];
  for (const [jobName, job] of Object.entries(releaseJobs)) {
    if (job.permissions === undefined) {
      continue;
    }
    if (typeof job.permissions === "string") {
      assert.equal(job.permissions, "read-all", `${jobName} must not use a broad permission preset`);
      continue;
    }
    assert.equal(typeof job.permissions, "object", `${jobName} permissions must be a map or read-all`);
    for (const value of Object.values(job.permissions)) {
      assert.match(value, /^(?:read|write|none)$/, `${jobName} has an unknown permission level`);
    }
    if (Object.values(job.permissions).includes("write")) {
      writeJobs.push(jobName);
    }
  }
  assert.deepEqual(writeJobs, ["publish"]);
  assert.deepEqual(releaseJobs.publish.permissions, {
    actions: "read",
    contents: "write",
    issues: "write",
  });
  assert.equal(releaseJobs.validate.needs, "detect");
  assert.deepEqual(releaseJobs.sign.needs, ["detect", "validate"]);
  assert.deepEqual(releaseJobs.publish.needs, ["detect", "sign"]);

  assert.match(verifier, /gh release download/);
  assert.match(verifier, /remote_digest/);
  assert.match(verifier, /codesign --verify --deep --strict/);
  assert.match(verifier, /codesign -d --extract-certificates/);
  assert.match(verifier, /openssl x509[\s\S]*?-fingerprint[\s\S]*?-sha256/);
  assert.match(verifier, /actual_certificate_sha256" = "\$expected_certificate_sha256/);
  assert.match(verifier, /verify_signer "\$\{assets_dir\}\/\$\{release_dmg_name\}" dmg-container/);
  assert.match(verifier, /\/usr\/bin\/env -u GH_TOKEN -u GITHUB_TOKEN "\$candidate_executable" --self-test/);
  assert.match(verifier, /test "\$dmg_entries" = \$'Applications\\nmd2png\.app'/);
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
  assert.match(release, /git show "\$\{WORKFLOW_COMMIT\}:scripts\/release-assets\.mjs"/);
  assert.match(release, /git show "\$\{WORKFLOW_COMMIT\}:scripts\/release-assets\.json"/);
  assert.match(release, /git show "\$\{WORKFLOW_COMMIT\}:scripts\/release-manifest\.mjs"/);
  assert.match(release, /git show "\$\{WORKFLOW_COMMIT\}:scripts\/release-milestone\.mjs"/);
  assert.match(release, /RELEASE_ASSETS_SCRIPT/);
  assert.match(release, /RELEASE_MANIFEST_SCRIPT/);
  assert.match(release, /RELEASE_MILESTONE_SCRIPT/);
  assert.match(release, /run: REPO_ROOT="\$GITHUB_WORKSPACE" "\$TRUSTED_PUBLISHER"/);
});

test("release remains draft until every uploaded asset has been verified", () => {
  const publisher = fs.readFileSync(path.join(repoRoot, "scripts/publish-hosted-release.sh"), "utf8");
  const resolveReleaseId = publisher.indexOf("--json databaseId");
  const releaseEndpoint = publisher.indexOf('release_endpoint="repos/${gh_repo}/releases/${release_id}"');
  const createDraft = publisher.indexOf("--draft");
  const upload = publisher.indexOf("gh release upload");
  const exactAssetSet = publisher.indexOf('if [[ "$published_names" != "$expected_names_text" ]]');
  const milestone = publisher.indexOf('"$release_milestone_script" sync');
  const publish = publisher.indexOf('--draft=false --latest');

  assert.ok(resolveReleaseId >= 0, "draft Releases must be resolved through gh release view");
  assert.ok(releaseEndpoint > resolveReleaseId, "Release API reads must use the resolved database ID");
  assert.doesNotMatch(publisher, /releases\/tags\//);
  assert.ok(createDraft >= 0, "new releases must start as drafts");
  assert.ok(upload > createDraft, "assets must upload after draft creation");
  assert.ok(exactAssetSet > upload, "the complete asset set must be verified after upload");
  assert.ok(milestone > exactAssetSet, "the release milestone must be synchronized after asset verification");
  assert.ok(publish > milestone, "the Release must remain draft until milestone synchronization succeeds");
  assert.ok(publish > exactAssetSet, "the draft must publish only after asset verification");
  assert.match(publisher, /Published Release is missing a verified asset/);
  assert.match(publisher, /jq -c --arg name "\$name"/);
  assert.doesNotMatch(publisher, /select\(\.name == \\"\$\{name\}/);
  assert.match(publisher, /published_release_json=.*"\$release_endpoint"/);
  assert.match(publisher, /\.draft <<< "\$published_release_json"\)" = "false"/);
});

test("Release PR previews and trusted publication applies the issue milestone", () => {
  const prepare = workflows["prepare-release-pr.yml"];
  const publisher = fs.readFileSync(path.join(repoRoot, "scripts/publish-hosted-release.sh"), "utf8");

  assert.match(prepare, /release-milestone\.mjs plan/);
  assert.match(prepare, /Release-Milestone-Plan-SHA256:/);
  assert.match(workflows["release-preflight.yml"], /release-milestone\.mjs plan/);
  assert.match(workflows["release-preflight.yml"], /Release-Milestone-Plan-SHA256:/);
  assert.match(workflows["release.yml"], /milestone_plan_sha256/);
  assert.match(prepare, /Planned .* issue milestone/);
  assert.match(publisher, /"\$release_milestone_script" sync/);
  assert.match(publisher, /--expected-review-digest "\$expected_milestone_plan_sha256"/);
  assert.match(publisher, /--tag "\$tag"/);
  assert.match(publisher, /--source-commit "\$source_commit"/);
});

test("the reviewed milestone digest is bound from preparation through publication", () => {
  const prepareWorkflow = parseYaml(workflows["prepare-release-pr.yml"]);
  const preflightWorkflow = parseYaml(workflows["release-preflight.yml"]);
  const releaseWorkflow = parseYaml(workflows["release.yml"]);
  const prepare = prepareWorkflow.jobs.prepare.steps.find(
    (step) => step.name === "Create focused release branch and pull request",
  ).run;
  const preflightStep = preflightWorkflow.jobs.detect.steps.find(
    (step) => step.name === "Validate release metadata change",
  );
  const preflight = preflightStep.run;
  const authorize = releaseWorkflow.jobs.detect.steps.find(
    (step) => step.name === "Validate release authorization",
  ).run;
  const publish = releaseWorkflow.jobs.publish;

  assert.ok(prepare.indexOf("release-milestone.mjs plan") < prepare.indexOf("git commit"));
  assert.match(prepare, /Release-Base: \$\{BASE_SHA\}/);
  assert.match(prepare, /Release-Milestone-Plan-SHA256: \$\{milestone_plan_sha256\}/);
  assert.match(preflight, /test "\$release_base" = "\$BASE_SHA"/);
  assert.match(preflight, /git rev-parse "\$\{HEAD_SHA\}\^1"/);
  assert.match(preflight, /git rev-list --count "\$\{BASE_SHA\}\.\.\$\{HEAD_SHA\}"/);
  assert.match(preflight, /release-milestone\.mjs plan[\s\S]*?\.reviewDigest[\s\S]*?milestone_plan_sha256/);
  assert.equal(preflightStep.env.GH_TOKEN, "${{ github.token }}");
  assert.equal(preflightStep.env.GITHUB_TOKEN, "${{ github.token }}");
  assert.match(authorize, /git\/commits\/\$\{pr_head_sha\}/);
  assert.match(authorize, /Release-Milestone-Plan-SHA256:/);
  assert.equal(
    publish.env.EXPECTED_MILESTONE_PLAN_SHA256,
    "${{ needs.detect.outputs.milestone_plan_sha256 }}",
  );
});
