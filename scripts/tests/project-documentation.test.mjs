import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
const latestDmg = "https://github.com/guangyya/md2png/releases/latest/download/md2png-latest.dmg";

test("user-facing entry points describe install, files, settings, and rounded output", () => {
  const english = read("README.md");
  const chinese = read("README.zh-Hans.md");

  for (const content of [english, chinese]) {
    assert.match(content, new RegExp(latestDmg.replaceAll(".", String.raw`\.`)));
    assert.match(content, /Finder/);
    assert.match(content, /Settings|设置/);
    assert.match(content, /Rounded Corners|圆角/);
  }
  assert.doesNotMatch(english, /^\| Launch at Login \|/m);
  assert.doesNotMatch(chinese, /^\| 登录时启动 \|/m);
});

test("security policy matches the Sparkle ZIP update authority", () => {
  const security = read("SECURITY.md");

  assert.match(security, /Sparkle/);
  assert.match(security, /versioned HTTPS ZIP/);
  assert.match(security, /EdDSA archive\s+signature/);
  assert.match(security, /DMG remains\s+an explicit[\s\S]*installation and recovery path/);
  assert.doesNotMatch(security, /download accepts only the expected[\s\S]*DMG/);
});

test("issue forms route bugs and feature requests without a duplicate backlog file", () => {
  const feature = read(".github/ISSUE_TEMPLATE/feature_request.yml");
  const bug = read(".github/ISSUE_TEMPLATE/bug_report.yml");
  const config = read(".github/ISSUE_TEMPLATE/config.yml");

  assert.doesNotMatch(feature, /BACKLOG\.md|Last Render window/);
  assert.match(feature, /public issues/);
  for (const field of ["version", "entry-point", "steps", "expected", "actual", "self-test", "checks"]) {
    assert.match(bug, new RegExp(`id: ${field}(?:\\n|$)`));
  }
  assert.match(bug, /confidential Markdown/);
  assert.match(bug, /never uploads diagnostics automatically/);
  assert.match(config, /blank_issues_enabled: false/);
  assert.match(config, /TROUBLESHOOTING\.md/);
  assert.match(config, /security\/advisories\/new/);
});

test("every issue template remains valid YAML", () => {
  for (const relativePath of [
    ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/ISSUE_TEMPLATE/config.yml",
    ".github/ISSUE_TEMPLATE/feature_request.yml",
  ]) {
    const result = spawnSync("/usr/bin/ruby", [
      "-ryaml",
      "-e",
      "YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)",
      path.join(repoRoot, relativePath),
    ], { encoding: "utf8" });
    assert.equal(result.status, 0, `${relativePath}: ${result.stderr}`);
  }
});

test("localized website copy includes file input and optional transparent corners", () => {
  const english = JSON.parse(read("site-src/locales/en.json"));
  const chinese = JSON.parse(read("site-src/locales/zh-Hans.json"));

  assert.match(english.meta.description, /local-file Markdown/);
  assert.match(chinese.meta.description, /本地文件中的 Markdown/);
  assert.match(english.features.items[0].description, /transparent rounded corners/);
  assert.match(chinese.features.items[0].description, /透明圆角/);
  assert.doesNotMatch(english.features.items[0].description, /opaque PNG/);
  assert.doesNotMatch(chinese.features.items[0].description, /不透明 PNG/);
});

test("site-only Make targets do not evaluate Node-backed release paths", () => {
  const result = spawnSync("make", [
    "--no-print-directory",
    "-n",
    "site-check",
    "NODE=/definitely/missing/node",
  ], { cwd: repoRoot, encoding: "utf8" });

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stderr, /missing\/node|not found/);
});

test("Debug apps omit Finder registrations unless integration testing opts in", () => {
  const makefile = read("Makefile");

  assert.match(makefile, /DEBUG_FINDER_INTEGRATION \?= 0/);
  assert.match(makefile, /LSREGISTER := .*LaunchServices.*lsregister/);
  assert.match(makefile, /"\$\(LSREGISTER\)" -u "\$\(APP_DIR\)"/);
  assert.match(makefile, /plutil -remove CFBundleDocumentTypes/);
  assert.match(makefile, /plutil -remove NSServices/);
  assert.match(makefile, /DEBUG_FINDER_INTEGRATION must be 0 or 1/);
});
