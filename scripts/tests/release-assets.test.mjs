import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  readReleaseAssetContract,
  releaseAsset,
  releaseAssetNames,
  releaseAssets,
  validateReleaseAssetContract,
  validateReleaseAssetSet,
} from "../release-assets.mjs";

const scriptPath = fileURLToPath(new URL("../release-assets.mjs", import.meta.url));
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const version = "0.4.0";

const expected = [
  {
    key: "releaseZip",
    name: "md2png-0.4.0-macOS-arm64-developer-id.zip",
    label: "md2png 0.4.0 — macOS app archive (Apple silicon)",
    contentType: "application/zip",
    sourcePath: "dist/md2png-0.4.0-macOS-arm64-developer-id.zip",
  },
  {
    key: "releaseDmg",
    name: "md2png-0.4.0-macOS-arm64-developer-id.dmg",
    label: "md2png 0.4.0 — macOS installer (Apple silicon)",
    contentType: "application/x-apple-diskimage",
    sourcePath: "dist/md2png-0.4.0-macOS-arm64-developer-id.dmg",
  },
  {
    key: "latestDmg",
    name: "md2png-latest.dmg",
    label: "md2png — latest macOS installer (Apple silicon)",
    contentType: "application/x-apple-diskimage",
    sourcePath: "dist/md2png-latest.dmg",
  },
  {
    key: "coverageJson",
    name: "md2png-0.4.0-coverage.json",
    label: "md2png 0.4.0 — normalized source-line coverage (JSON)",
    contentType: "application/json",
    sourcePath: ".build/coverage/md2png-0.4.0-coverage.json",
  },
  {
    key: "coverageMarkdown",
    name: "md2png-0.4.0-coverage.md",
    label: "md2png 0.4.0 — source-line coverage summary (Markdown)",
    contentType: "application/octet-stream",
    sourcePath: ".build/coverage/md2png-0.4.0-coverage.md",
  },
];

test("renders the reviewed release asset contract exactly", () => {
  assert.deepEqual(releaseAssets(version), expected);
  assert.deepEqual(releaseAssetNames(version), expected.map((asset) => asset.name));
  assert.deepEqual(releaseAsset(version, "coverageJson"), expected[3]);
});

test("treats JSON membership as authoritative and rejects malformed contract entries", () => {
  const contract = readReleaseAssetContract();
  const clone = () => structuredClone(contract);
  const reordered = clone();
  [reordered.assets[0], reordered.assets[1]] = [reordered.assets[1], reordered.assets[0]];
  assert.equal(validateReleaseAssetContract(reordered), reordered);
  const empty = clone();
  empty.assets = [];
  assert.throws(() => validateReleaseAssetContract(empty), /at least one asset/);
  const duplicate = clone();
  duplicate.assets[1].key = duplicate.assets[0].key;
  assert.throws(() => validateReleaseAssetContract(duplicate), /keys must be unique/);
  const unknownField = clone();
  unknownField.assets[0].typo = true;
  assert.throws(() => validateReleaseAssetContract(unknownField), /fields must be exactly/);
  const unknownToken = clone();
  unknownToken.assets[0].name = "md2png-{branch}.zip";
  assert.throws(() => validateReleaseAssetContract(unknownToken), /unsupported template token/);
  const unsafePath = clone();
  unsafePath.assets[0].sourcePath = "../{name}";
  assert.throws(() => releaseAssets(version, unsafePath), /unsafe or mismatched sourcePath/);
  const unsafeName = clone();
  unsafeName.assets[0].name = 'bad"name.zip';
  unsafeName.assets[0].sourcePath = "dist/{name}";
  assert.throws(() => releaseAssets(version, unsafeName), /unsafe asset name/);
  assert.throws(() => releaseAsset(version, "missing"), /unknown release asset key/);
});

test("rejects missing, extra, renamed, mislabeled, and mistyped published sets", () => {
  const metadata = expected.map(({ name, label, contentType }) => ({ name, label, contentType }));
  assert.equal(validateReleaseAssetSet(metadata, version), metadata);
  const mutations = [
    metadata.slice(1),
    [...metadata, { name: "extra.zip", label: "extra", contentType: "application/zip" }],
    metadata.map((asset, index) => index === 0 ? { ...asset, name: "renamed.zip" } : asset),
    metadata.map((asset, index) => index === 0 ? { ...asset, label: "wrong label" } : asset),
    metadata.map((asset, index) => index === 0 ? { ...asset, contentType: "text/plain" } : asset),
  ];
  for (const mutation of mutations) {
    assert.throws(() => validateReleaseAssetSet(mutation, version), /does not exactly match/);
  }
});

test("CLI emits JSON and names from the same contract", () => {
  const json = spawnSync(process.execPath, [scriptPath, "json", "--version", version], { encoding: "utf8" });
  assert.equal(json.status, 0, json.stderr);
  assert.deepEqual(JSON.parse(json.stdout), { schemaVersion: 1, version, assets: expected });
  const names = spawnSync(process.execPath, [scriptPath, "names", "--version", version], { encoding: "utf8" });
  assert.equal(names.status, 0, names.stderr);
  assert.deepEqual(names.stdout.trim().split("\n"), expected.map((asset) => asset.name));
  const invalid = spawnSync(process.execPath, [scriptPath, "json", "--version", "0.4.0-beta.1"], { encoding: "utf8" });
  assert.equal(invalid.status, 1);
  assert.match(invalid.stderr, /stable semantic version/);
  const field = spawnSync(process.execPath, [
    scriptPath, "field", "--version", version, "--key", "releaseDmg", "--field", "sourcePath",
  ], { encoding: "utf8" });
  assert.equal(field.status, 0, field.stderr);
  assert.equal(field.stdout.trim(), expected[1].sourcePath);
});

test("release tooling consumes the contract instead of redefining canonical asset metadata", () => {
  const consumers = [
    "scripts/release-manifest.mjs",
    "scripts/release-automation.mjs",
    "scripts/coverage-history.mjs",
    "scripts/publish-release.sh",
    "scripts/publish-hosted-release.sh",
    "scripts/verify-published-release.sh",
    ".github/workflows/release.yml",
    ".github/workflows/release-preflight.yml",
    "Makefile",
  ];
  for (const relativePath of consumers) {
    const content = fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
    assert.match(content, /release-assets/, `${relativePath} must consume the release asset contract`);
    assert.doesNotMatch(content, /md2png-latest\.dmg|md2png-.*developer-id\.(?:zip|dmg)|md2png-.*coverage\.(?:json|md)/, `${relativePath} redefines an asset name`);
    assert.doesNotMatch(content, /macOS app archive \(Apple silicon\)|normalized source-line coverage \(JSON\)/, `${relativePath} redefines an asset label`);
    if (relativePath !== "scripts/coverage-history.mjs") {
      assert.doesNotMatch(content, /application\/x-apple-diskimage|application\/octet-stream/, `${relativePath} redefines an asset content type`);
    }
  }
});

test("Makefile producers resolve canonical release paths from the contract", () => {
  const producerVersion = "9.8.7";
  const result = spawnSync("make", [
    "--no-print-directory",
    "-s",
    "release-asset-paths",
    `NODE=${process.execPath}`,
    `VERSION=${producerVersion}`,
    "RELEASE_SUFFIX=developer-id",
  ], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  const actual = Object.fromEntries(result.stdout.trim().split("\n").map((line) => line.split("=")));
  assert.deepEqual(actual, Object.fromEntries(releaseAssets(producerVersion)
    .filter((asset) => asset.key !== "latestDmg")
    .map((asset) => [asset.key, asset.sourcePath])));
});
