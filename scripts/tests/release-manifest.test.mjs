import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { createManifest, validateManifest } from "../release-manifest.mjs";

const scriptPath = fileURLToPath(new URL("../release-manifest.mjs", import.meta.url));

const version = "0.4.0";
const build = "4";
const commit = "0123456789abcdef0123456789abcdef01234567";

function fixture() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "md2png-manifest-test-"));
  const files = [
    `md2png-${version}-macOS-arm64-developer-id.zip`,
    `md2png-${version}-macOS-arm64-developer-id.dmg`,
    "md2png-latest.dmg",
    `md2png-${version}-coverage.json`,
    `md2png-${version}-coverage.md`,
  ];
  for (const name of files) {
    fs.writeFileSync(path.join(directory, name), name.endsWith(".dmg") ? "same dmg" : `content:${name}`);
  }
  return { directory, files };
}

test("creates a normalized manifest and validates every handoff digest", (context) => {
  const { directory, files } = fixture();
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const manifest = createManifest({ directory, files, version, build, commit });
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.assets.length, 5);
  assert.deepEqual([...manifest.assets].map((asset) => asset.name), [...files].sort());
  assert.equal(validateManifest({ manifest, directory, version, build, commit }), manifest);
});

test("rejects a changed asset after manifest creation", (context) => {
  const { directory, files } = fixture();
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const manifest = createManifest({ directory, files, version, build, commit });
  fs.appendFileSync(path.join(directory, files[0]), "tampered");
  assert.throws(
    () => validateManifest({ manifest, directory, version, build, commit }),
    /size or digest/,
  );
});

test("rejects missing, extra, unsafe, and non-identical alias assets", (context) => {
  const { directory, files } = fixture();
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  assert.throws(
    () => createManifest({ directory, files: files.slice(1), version, build, commit }),
    /manifest assets must be exactly/,
  );
  assert.throws(
    () => createManifest({ directory, files: [...files.slice(0, -1), "../escape.md"], version, build, commit }),
    /invalid asset name/,
  );
  fs.writeFileSync(path.join(directory, "md2png-latest.dmg"), "different");
  assert.throws(
    () => createManifest({ directory, files, version, build, commit }),
    /byte-identical/,
  );
  fs.unlinkSync(path.join(directory, "md2png-latest.dmg"));
  fs.symlinkSync(`md2png-${version}-macOS-arm64-developer-id.dmg`, path.join(directory, "md2png-latest.dmg"));
  assert.throws(
    () => createManifest({ directory, files, version, build, commit }),
    /asset is missing or empty/,
  );
});

test("rejects identity and schema drift", (context) => {
  const { directory, files } = fixture();
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const manifest = createManifest({ directory, files, version, build, commit });
  assert.throws(
    () => validateManifest({ manifest, directory, version: "0.4.1", build, commit }),
    /release identity/,
  );
  assert.throws(
    () => validateManifest({ manifest: { ...manifest, schemaVersion: 2 }, directory, version, build, commit }),
    /unsupported manifest/,
  );
  assert.throws(
    () => createManifest({ directory, files, version, build: "999999999999999999999", commit }),
    /build exceeds the safe integer range/,
  );
});

test("manifest CLI rejects unknown and duplicate scalar options", () => {
  const unknown = spawnSync(process.execPath, [
    scriptPath,
    "validate",
    "--directory", ".",
    "--version", version,
    "--build", build,
    "--commit", commit,
    "--manifest", "missing.json",
    "--typo", "x",
  ], { encoding: "utf8" });
  assert.equal(unknown.status, 1);
  assert.match(unknown.stderr, /unknown option: --typo/);
  const duplicate = spawnSync(process.execPath, [
    scriptPath,
    "validate",
    "--directory", ".",
    "--version", version,
    "--version", "0.5.0",
    "--build", build,
    "--commit", commit,
    "--manifest", "missing.json",
  ], { encoding: "utf8" });
  assert.equal(duplicate.status, 1);
  assert.match(duplicate.stderr, /duplicate option: --version/);
});
