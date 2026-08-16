import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const helper = path.join(repoRoot, "scripts/release-update-channel.sh");
const contract = "md2png stable update channel contract v1\n";

function plist(values = {}) {
  const entries = Object.entries(values).map(([key, value]) => (
    `    <key>${key}</key>\n    <string>${value}</string>`
  )).join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${entries}
</dict>
</plist>
`;
}

function runHelper(cwd, command, sourceCommit, workflowCommit, plistPath) {
  return spawnSync("/bin/bash", [
    helper,
    command,
    "--source-commit",
    sourceCommit,
    "--workflow-commit",
    workflowCommit,
    "--plist",
    plistPath,
  ], { cwd, encoding: "utf8" });
}

test("trusted update-channel boundary supports legacy recovery without weakening new releases", (context) => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), "md2png-update-channel-"));
  context.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const git = (...args) => execFileSync("git", args, { cwd: fixture, encoding: "utf8" }).trim();
  git("init", "-b", "main");
  git("config", "user.name", "Release Test");
  git("config", "user.email", "release-test@example.invalid");

  fs.writeFileSync(path.join(fixture, "Info.plist"), plist());
  git("add", "Info.plist");
  git("commit", "-m", "Legacy release source");
  const legacyCommit = git("rev-parse", "HEAD");

  fs.mkdirSync(path.join(fixture, "scripts"));
  fs.writeFileSync(path.join(fixture, "scripts/release-update-channel-contract-v1"), contract);
  fs.writeFileSync(path.join(fixture, "Info.plist"), plist({ MD2PNGUpdateChannel: "disabled" }));
  git("add", "Info.plist", "scripts/release-update-channel-contract-v1");
  git("commit", "-m", "Introduce update channel contract");
  fs.writeFileSync(path.join(fixture, "README.md"), "post-contract source\n");
  git("add", "README.md");
  git("commit", "-m", "Post-contract release source");
  const workflowCommit = git("rev-parse", "HEAD");
  const postContractCommit = workflowCommit;

  git("checkout", "--detach", legacyCommit);
  let result = runHelper(fixture, "prepare-source", legacyCommit, workflowCommit, "Info.plist");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(execFileSync("/usr/libexec/PlistBuddy", [
    "-c",
    "Print :MD2PNGUpdateChannel",
    path.join(fixture, "Info.plist"),
  ], { encoding: "utf8" }).trim(), "stable");

  const freshLegacyApp = path.join(fixture, "fresh-legacy-app.plist");
  fs.copyFileSync(path.join(fixture, "Info.plist"), freshLegacyApp);
  result = runHelper(fixture, "validate-app", legacyCommit, workflowCommit, freshLegacyApp);
  assert.equal(result.status, 0, result.stderr);

  const legacyApp = path.join(fixture, "legacy-app.plist");
  fs.writeFileSync(legacyApp, plist());
  result = runHelper(fixture, "validate-app", legacyCommit, workflowCommit, legacyApp);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /source predates the update-channel contract/);

  fs.writeFileSync(legacyApp, plist({ MD2PNGDebugCheckoutID: "debug-checkout" }));
  result = runHelper(fixture, "validate-app", legacyCommit, workflowCommit, legacyApp);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /must not carry a debug checkout identity/);

  fs.writeFileSync(legacyApp, plist({ MD2PNGUpdateChannel: "nightly" }));
  result = runHelper(fixture, "validate-app", legacyCommit, workflowCommit, legacyApp);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /must be exactly stable/);

  fs.writeFileSync(path.join(fixture, "Info.plist"), plist());
  git("checkout", "--detach", postContractCommit);
  const currentApp = path.join(fixture, "current-app.plist");
  fs.writeFileSync(currentApp, plist());
  result = runHelper(fixture, "validate-app", postContractCommit, workflowCommit, currentApp);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /must carry the stable update channel/);

  fs.writeFileSync(currentApp, plist({ MD2PNGUpdateChannel: "stable" }));
  result = runHelper(fixture, "validate-app", postContractCommit, workflowCommit, currentApp);
  assert.equal(result.status, 0, result.stderr);

  result = runHelper(fixture, "prepare-source", postContractCommit, workflowCommit, "Info.plist");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(execFileSync("/usr/libexec/PlistBuddy", [
    "-c",
    "Print :MD2PNGUpdateChannel",
    path.join(fixture, "Info.plist"),
  ], { encoding: "utf8" }).trim(), "stable");
});
