import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  canonicalExecutablePath,
  checkoutIdentity,
  commandMatchesExecutable,
  debugBundleIdentifier,
  isIgnorableKillError,
  matchingProcessIDs,
  parseOptions,
  parseProcessTable,
  shouldRetryOpenFailure
} from "../debug-run.mjs";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));

function configuredAppPaths(configuration) {
  const makefile = `include Makefile
.PHONY: print-app-paths
print-app-paths:
\t@printf '%s|%s\\n' "$(APP_DIR)" "$(CONTENTS)"
`;
  const result = spawnSync(
    "/usr/bin/make",
    ["--no-print-directory", "-s", "-f", "-", `CONFIGURATION=${configuration}`, "print-app-paths"],
    { cwd: repoRoot, encoding: "utf8", input: makefile }
  );
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim().split("|");
}

test("derives a stable checkout identity from the canonical checkout path", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "md2png-debug-run-"));
  try {
    const first = path.join(root, "first");
    const second = path.join(root, "second");
    const alias = path.join(root, "first-alias");
    mkdirSync(first);
    mkdirSync(second);
    symlinkSync(first, alias);

    assert.match(checkoutIdentity(first), /^[0-9a-f]{12}$/);
    assert.equal(checkoutIdentity(first), checkoutIdentity(realpathSync(first)));
    assert.equal(checkoutIdentity(first), checkoutIdentity(alias));
    assert.notEqual(checkoutIdentity(first), checkoutIdentity(second));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("adds the checkout identity only to a validated Debug bundle identifier", () => {
  assert.equal(
    debugBundleIdentifier("io.github.example.md2png", "0123456789ab"),
    "io.github.example.md2png.debug-0123456789ab"
  );
  assert.throws(
    () => debugBundleIdentifier("io.github.example/md2png", "0123456789ab"),
    /unsupported characters/
  );
  assert.throws(
    () => debugBundleIdentifier("io.github.example.md2png", "not-an-id"),
    /12 lowercase hexadecimal/
  );
});

test("keeps Debug output separate from same-checkout Release output", () => {
  assert.deepEqual(configuredAppPaths("release"), [
    "dist/md2png.app",
    "dist/md2png.app/Contents"
  ]);
  assert.deepEqual(configuredAppPaths("debug"), [
    "dist/debug/md2png.app",
    "dist/debug/md2png.app/Contents"
  ]);
});

test("selects only the exact Debug executable path for the current checkout", () => {
  const currentExecutable = "/worktrees/one/dist/debug/md2png.app/Contents/MacOS/md2png";
  const processes = parseProcessTable(`
  101 ${currentExecutable}
  102 /Applications/md2png.app/Contents/MacOS/md2png
  103 /worktrees/one/dist/md2png.app/Contents/MacOS/md2png
  104 /worktrees/two/dist/debug/md2png.app/Contents/MacOS/md2png
  105 ${currentExecutable} --unexpected-argument
  106 helper ${currentExecutable}
  `);

  assert.deepEqual(matchingProcessIDs(processes, currentExecutable, 999), [101]);
  assert.deepEqual(matchingProcessIDs(processes, currentExecutable, 101), []);
});

test("matches executable aliases by canonical path without accepting arguments", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "md2png-debug-run-path-"));
  try {
    const checkout = path.join(root, "checkout");
    const alias = path.join(root, "checkout-alias");
    const executable = path.join(checkout, "dist", "md2png.app", "Contents", "MacOS", "md2png");
    mkdirSync(path.dirname(executable), { recursive: true });
    writeFileSync(executable, "");
    symlinkSync(checkout, alias);
    const aliasedExecutable = path.join(alias, "dist", "md2png.app", "Contents", "MacOS", "md2png");
    const canonicalExecutable = realpathSync.native(executable);

    assert.equal(canonicalExecutablePath(aliasedExecutable), canonicalExecutable);
    assert.equal(commandMatchesExecutable(aliasedExecutable, executable), true);
    assert.equal(commandMatchesExecutable(`${aliasedExecutable} --argument`, executable), false);

    rmSync(executable);
    assert.equal(canonicalExecutablePath(aliasedExecutable), canonicalExecutable);
    assert.equal(commandMatchesExecutable(aliasedExecutable, executable), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("tolerates only vanished or unsignalable process errors", () => {
  assert.equal(isIgnorableKillError({ code: "ESRCH" }), true);
  assert.equal(isIgnorableKillError({ code: "EPERM" }), true);
  assert.equal(isIgnorableKillError({ code: "EINVAL" }), false);
  assert.equal(isIgnorableKillError(new Error("missing code")), false);
});

test("rejects unknown, duplicate, and incomplete command options", () => {
  assert.deepEqual(
    parseOptions(["--repo-root", "/repo", "--base", "io.example.app"], [
      "repo-root",
      "base"
    ]),
    { "repo-root": "/repo", base: "io.example.app" }
  );
  assert.throws(() => parseOptions(["--unknown", "x"], ["repo-root"]), /unknown/);
  assert.throws(
    () => parseOptions(["--repo-root", "/one", "--repo-root", "/two"], ["repo-root"]),
    /duplicate/
  );
  assert.throws(() => parseOptions(["--repo-root"], ["repo-root"]), /missing value/);
});

test("retries only the transient LaunchServices termination race", () => {
  assert.equal(
    shouldRetryOpenFailure("_LSOpenURLsWithCompletionHandler() failed with error -600."),
    true
  );
  assert.equal(
    shouldRetryOpenFailure("_LSOpenURLsWithCompletionHandler() failed with error -609."),
    true
  );
  assert.equal(shouldRetryOpenFailure("The application cannot be found."), false);
  assert.equal(shouldRetryOpenFailure("failed with error -10810"), false);
});
