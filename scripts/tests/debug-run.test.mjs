import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  checkoutIdentity,
  debugBundleIdentifier,
  matchingProcessIDs,
  parseOptions,
  parseProcessTable,
  shouldRetryOpenFailure
} from "../debug-run.mjs";

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

test("selects only the exact executable path for the current checkout", () => {
  const currentExecutable = "/worktrees/one/dist/md2png.app/Contents/MacOS/md2png";
  const processes = parseProcessTable(`
  101 ${currentExecutable}
  102 /Applications/md2png.app/Contents/MacOS/md2png
  103 /worktrees/two/dist/md2png.app/Contents/MacOS/md2png
  104 ${currentExecutable} --unexpected-argument
  105 helper ${currentExecutable}
  `);

  assert.deepEqual(matchingProcessIDs(processes, currentExecutable, 999), [101]);
  assert.deepEqual(matchingProcessIDs(processes, currentExecutable, 101), []);
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
