import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  deriveBump,
  inspectRelease,
  nextVersion,
  parsePlistMetadata,
  planRelease,
  prepareRelease,
  releaseDateForInstant,
  validatePreparedRelease,
} from "../release-automation.mjs";

const scriptPath = fileURLToPath(new URL("../release-automation.mjs", import.meta.url));

const plist = (version = "0.3.0", build = "3") => `<?xml version="1.0"?>
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${build}</string>
</dict>
</plist>
`;

const changelog = (bullet = "A complete change") => `# Changelog

## [Unreleased]

### Added

- ${bullet}

## [0.3.0] - 2026-08-14

### Added

- Previous release
`;

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "md2png-release-test-"));
  fs.writeFileSync(path.join(root, "Info.plist"), plist());
  fs.writeFileSync(path.join(root, "CHANGELOG.md"), changelog("Complete details"));
  fs.writeFileSync(path.join(root, "ABOUT_CHANGELOG.md"), changelog("Concise highlight"));
  return root;
}

function copyFixture(source) {
  const target = fs.mkdtempSync(path.join(os.tmpdir(), "md2png-release-copy-"));
  fs.cpSync(source, target, { recursive: true });
  return target;
}

test("calculates exact patch, minor, and major versions including 0.x", () => {
  assert.equal(nextVersion("0.3.0", "patch"), "0.3.1");
  assert.equal(nextVersion("0.3.0", "minor"), "0.4.0");
  assert.equal(nextVersion("0.3.0", "major"), "1.0.0");
  assert.equal(deriveBump("0.3.0", "0.3.1"), "patch");
  assert.equal(deriveBump("0.3.0", "0.4.0"), "minor");
  assert.equal(deriveBump("0.3.0", "1.0.0"), "major");
  assert.throws(() => deriveBump("0.3.0", "0.5.0"), /not an exact/);
});

test("uses the documented Asia/Shanghai date at the UTC boundary", () => {
  assert.equal(releaseDateForInstant("2026-08-14T15:59:59Z"), "2026-08-14");
  assert.equal(releaseDateForInstant("2026-08-14T16:00:00Z"), "2026-08-15");
  assert.throws(() => releaseDateForInstant("not-an-instant"), /release instant is invalid/);
});

test("rejects prerelease, skipped bump names, and invalid build numbers", () => {
  assert.throws(() => nextVersion("0.3.0-beta.1", "patch"), /stable semantic version/);
  assert.throws(() => nextVersion("0.3.0", "banana"), /bump must be one of/);
  assert.throws(() => parsePlistMetadata(plist("0.3.0", "0")), /positive integer/);
});

test("prepares exactly the next version and build from both Unreleased sections", (context) => {
  const root = fixture();
  context.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const plan = prepareRelease({ repoRoot: root, bump: "minor", date: "2026-08-15" });
  assert.equal(plan.version, "0.4.0");
  assert.equal(plan.build, 4);
  assert.equal(plan.branch, "codex/release-v0.4.0");
  assert.deepEqual(inspectRelease(root), {
    version: "0.4.0",
    build: 4,
    changelogUnreleased: "",
    aboutUnreleased: "",
  });
  for (const name of ["CHANGELOG.md", "ABOUT_CHANGELOG.md"]) {
    const content = fs.readFileSync(path.join(root, name), "utf8");
    assert.match(content, /^## \[Unreleased\]\n\n## \[0\.4\.0\] - 2026-08-15/m);
  }
});

test("plans without modifying release files", (context) => {
  const root = fixture();
  context.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const before = fs.readFileSync(path.join(root, "Info.plist"), "utf8");
  const plan = planRelease({ repoRoot: root, bump: "patch", date: "2026-08-15" });
  assert.equal(plan.version, "0.3.1");
  assert.equal(fs.readFileSync(path.join(root, "Info.plist"), "utf8"), before);
});

test("validates a prepared release against its exact base content", (context) => {
  const baseRoot = fixture();
  const repoRoot = copyFixture(baseRoot);
  context.after(() => fs.rmSync(baseRoot, { recursive: true, force: true }));
  context.after(() => fs.rmSync(repoRoot, { recursive: true, force: true }));
  prepareRelease({ repoRoot, bump: "patch", date: "2026-08-15" });
  const plan = validatePreparedRelease({ baseRoot, repoRoot, bump: "patch" });
  assert.equal(plan.version, "0.3.1");
  assert.equal(plan.oldBuild, 3);
  assert.equal(plan.date, "2026-08-15");
});

test("rejects empty and malformed Unreleased notes before writing", (context) => {
  const root = fixture();
  context.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.writeFileSync(path.join(root, "ABOUT_CHANGELOG.md"), "# About\n\n## [Unreleased]\n");
  assert.throws(
    () => prepareRelease({ repoRoot: root, bump: "patch", date: "2026-08-15" }),
    /ABOUT_CHANGELOG\.md \[Unreleased\] is empty/,
  );
  assert.equal(parsePlistMetadata(fs.readFileSync(path.join(root, "Info.plist"), "utf8")).version, "0.3.0");
});

test("rejects duplicate target sections and invalid dates", (context) => {
  const root = fixture();
  const invalidDateRoot = fixture();
  context.after(() => fs.rmSync(root, { recursive: true, force: true }));
  context.after(() => fs.rmSync(invalidDateRoot, { recursive: true, force: true }));
  fs.appendFileSync(path.join(root, "CHANGELOG.md"), "\n## [0.3.1] - 2026-08-15\n\n### Fixed\n\n- Duplicate\n");
  assert.throws(
    () => prepareRelease({ repoRoot: root, bump: "patch", date: "2026-08-15" }),
    /already contains \[0\.3\.1\]/,
  );
  assert.throws(
    () => prepareRelease({ repoRoot: invalidDateRoot, bump: "minor", date: "2026-02-30" }),
    /release date is invalid/,
  );
});

test("rejects a changelog whose Unreleased section is not first", (context) => {
  const root = fixture();
  context.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const content = fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8");
  fs.writeFileSync(
    path.join(root, "CHANGELOG.md"),
    content.replace("## [Unreleased]", "## [0.2.0] - 2026-08-13\n\n### Fixed\n\n- Old\n\n## [Unreleased]"),
  );
  assert.throws(
    () => prepareRelease({ repoRoot: root, bump: "patch", date: "2026-08-15" }),
    /must be the first version section/,
  );
});

test("rejects altered release notes, nonempty placeholders, and mismatched builds", (context) => {
  const baseRoot = fixture();
  const repoRoot = copyFixture(baseRoot);
  context.after(() => fs.rmSync(baseRoot, { recursive: true, force: true }));
  context.after(() => fs.rmSync(repoRoot, { recursive: true, force: true }));
  prepareRelease({ repoRoot, bump: "major", date: "2026-08-15" });
  fs.appendFileSync(path.join(repoRoot, "ABOUT_CHANGELOG.md"), "\n");
  let about = fs.readFileSync(path.join(repoRoot, "ABOUT_CHANGELOG.md"), "utf8");
  about = about.replace("- Concise highlight", "- Invented highlight");
  fs.writeFileSync(path.join(repoRoot, "ABOUT_CHANGELOG.md"), about);
  assert.throws(
    () => validatePreparedRelease({ baseRoot, repoRoot, bump: "major" }),
    /must exactly match the base \[Unreleased\] content/,
  );
});

test("rejects unrelated plist and historical changelog edits", (context) => {
  const baseRoot = fixture();
  const repoRoot = copyFixture(baseRoot);
  context.after(() => fs.rmSync(baseRoot, { recursive: true, force: true }));
  context.after(() => fs.rmSync(repoRoot, { recursive: true, force: true }));
  prepareRelease({ repoRoot, bump: "patch", date: "2026-08-15" });

  let plistContent = fs.readFileSync(path.join(repoRoot, "Info.plist"), "utf8");
  plistContent = plistContent.replace("<dict>", "<dict>\n  <key>Unexpected</key>\n  <string>value</string>");
  fs.writeFileSync(path.join(repoRoot, "Info.plist"), plistContent);
  assert.throws(
    () => validatePreparedRelease({ baseRoot, repoRoot }),
    /Info\.plist may change only/,
  );

  fs.writeFileSync(path.join(repoRoot, "Info.plist"), plist("0.3.1", "4"));
  let history = fs.readFileSync(path.join(repoRoot, "CHANGELOG.md"), "utf8");
  history = history.replace("- Previous release", "- Rewritten history");
  fs.writeFileSync(path.join(repoRoot, "CHANGELOG.md"), history);
  assert.throws(
    () => validatePreparedRelease({ baseRoot, repoRoot }),
    /changes outside the deterministic release transformation/,
  );
});

test("CLI rejects unknown and duplicate options", (context) => {
  const root = fixture();
  context.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const unknown = spawnSync(process.execPath, [scriptPath, "inspect", "--repo-root", root, "--typo", "x"], {
    encoding: "utf8",
  });
  assert.equal(unknown.status, 1);
  assert.match(unknown.stderr, /unknown option: --typo/);
  const duplicate = spawnSync(process.execPath, [
    scriptPath,
    "plan",
    "--repo-root", root,
    "--bump", "patch",
    "--bump", "minor",
    "--date", "2026-08-15",
  ], { encoding: "utf8" });
  assert.equal(duplicate.status, 1);
  assert.match(duplicate.stderr, /duplicate option: --bump/);
});
