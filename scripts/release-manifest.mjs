#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const schemaVersion = 1;
const stableVersionPattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const commitPattern = /^[0-9a-f]{40}$/;

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const [command, ...tokens] = argv;
  const options = {};
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!token.startsWith("--") || index + 1 >= tokens.length) {
      fail(`invalid argument: ${token}`);
    }
    const name = token.slice(2);
    const value = tokens[index + 1];
    if (name === "file") {
      options.file ??= [];
      options.file.push(value);
    } else {
      if (Object.hasOwn(options, name)) {
        fail(`duplicate option: --${name}`);
      }
      options[name] = value;
    }
    index += 1;
  }
  return { command, options };
}

function allowOnlyOptions(options, allowed) {
  const unknown = Object.keys(options).filter((name) => !allowed.includes(name));
  if (unknown.length > 0) {
    fail(`unknown option: --${unknown[0]}`);
  }
}

function required(options, name) {
  const value = options[name];
  if (!value || (Array.isArray(value) && value.length === 0)) {
    fail(`--${name} is required`);
  }
  return value;
}

function validateIdentity({ version, build, commit }) {
  if (!stableVersionPattern.test(version)) {
    fail("version must be a stable semantic version");
  }
  if (version.split(".").some((part) => !Number.isSafeInteger(Number(part)))) {
    fail("version exceeds the safe integer range");
  }
  if (!/^[1-9][0-9]*$/.test(String(build))) {
    fail("build must be a positive integer");
  }
  if (!Number.isSafeInteger(Number(build))) {
    fail("build exceeds the safe integer range");
  }
  if (!commitPattern.test(commit)) {
    fail("commit must be a lowercase 40-character SHA");
  }
}

function safeAssetName(name) {
  if (!name || name !== path.basename(name) || name === "." || name === "..") {
    fail(`invalid asset name: ${name}`);
  }
  return name;
}

function digestFile(filePath) {
  const content = fs.readFileSync(filePath);
  return {
    size: content.length,
    sha256: crypto.createHash("sha256").update(content).digest("hex"),
  };
}

function expectedAssetNames(version) {
  return [
    `md2png-${version}-macOS-arm64-developer-id.zip`,
    `md2png-${version}-macOS-arm64-developer-id.dmg`,
    "md2png-latest.dmg",
    `md2png-${version}-coverage.json`,
    `md2png-${version}-coverage.md`,
  ];
}

export function createManifest({ directory, files, version, build, commit }) {
  validateIdentity({ version, build, commit });
  const names = files.map(safeAssetName);
  if (new Set(names).size !== names.length) {
    fail("manifest asset names must be unique");
  }
  const expected = expectedAssetNames(version);
  if (JSON.stringify([...names].sort()) !== JSON.stringify([...expected].sort())) {
    fail(`manifest assets must be exactly: ${expected.join(", ")}`);
  }
  const assets = names.sort().map((name) => {
    const filePath = path.join(directory, name);
    const stat = fs.lstatSync(filePath);
    if (!stat.isFile() || stat.size <= 0) {
      fail(`asset is missing or empty: ${name}`);
    }
    return { name, ...digestFile(filePath) };
  });
  const versionedDmg = assets.find((asset) => asset.name.endsWith("-developer-id.dmg"));
  const latestDmg = assets.find((asset) => asset.name === "md2png-latest.dmg");
  if (versionedDmg.sha256 !== latestDmg.sha256 || versionedDmg.size !== latestDmg.size) {
    fail("md2png-latest.dmg must be byte-identical to the versioned DMG");
  }
  return {
    schemaVersion,
    version,
    build: Number(build),
    commit,
    tag: `v${version}`,
    assets,
  };
}

export function validateManifest({ manifest, directory, version, build, commit }) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    fail("manifest must be an object");
  }
  if (manifest.schemaVersion !== schemaVersion) {
    fail(`unsupported manifest schemaVersion: ${manifest.schemaVersion}`);
  }
  validateIdentity({ version, build, commit });
  if (manifest.version !== version || manifest.build !== Number(build) || manifest.commit !== commit) {
    fail("manifest release identity does not match the requested release");
  }
  if (manifest.tag !== `v${version}`) {
    fail("manifest tag does not match its version");
  }
  if (!Array.isArray(manifest.assets)) {
    fail("manifest assets must be an array");
  }
  const recreated = createManifest({
    directory,
    files: manifest.assets.map((asset) => asset?.name),
    version,
    build,
    commit,
  });
  if (JSON.stringify(recreated) !== JSON.stringify(manifest)) {
    fail("manifest asset size or digest does not match the handoff files");
  }
  return manifest;
}

function main(argv) {
  const { command, options } = parseArgs(argv);
  const directory = path.resolve(required(options, "directory"));
  const identity = {
    version: required(options, "version"),
    build: required(options, "build"),
    commit: required(options, "commit"),
  };
  if (command === "create") {
    allowOnlyOptions(options, ["directory", "version", "build", "commit", "file", "output"]);
    const manifest = createManifest({
      directory,
      files: required(options, "file"),
      ...identity,
    });
    const output = path.resolve(required(options, "output"));
    fs.writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
    process.stdout.write(`${output}\n`);
  } else if (command === "validate") {
    allowOnlyOptions(options, ["directory", "version", "build", "commit", "manifest"]);
    const manifestPath = path.resolve(required(options, "manifest"));
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    validateManifest({ manifest, directory, ...identity });
    process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
  } else {
    fail("usage: release-manifest.mjs create|validate [options]");
  }
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (invokedPath === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
