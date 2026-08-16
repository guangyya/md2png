#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const contractPath = fileURLToPath(new URL("./release-assets.json", import.meta.url));
const stableVersionPattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const assetFields = ["key", "name", "label", "contentType", "sourcePath"];

function fail(message) {
  throw new Error(message);
}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object`);
  }
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) {
    fail(`${label} fields must be exactly: ${wanted.join(", ")}`);
  }
}

function validateTemplate(value, allowedTokens, label) {
  if (typeof value !== "string" || value.trim() !== value || value.length === 0) {
    fail(`${label} must be a nonempty trimmed string`);
  }
  const tokens = [...value.matchAll(/\{([^{}]+)\}/g)].map((match) => match[1]);
  const unknown = tokens.find((token) => !allowedTokens.includes(token));
  if (unknown || value.replace(/\{[^{}]+\}/g, "").includes("{") || value.replace(/\{[^{}]+\}/g, "").includes("}")) {
    fail(`${label} contains an unsupported template token`);
  }
}

function renderTemplate(value, variables) {
  return value.replace(/\{([^{}]+)\}/g, (_match, token) => variables[token]);
}

export function validateReleaseAssetContract(contract) {
  exactKeys(contract, ["schemaVersion", "assets"], "release asset contract");
  if (contract.schemaVersion !== 1) {
    fail(`unsupported release asset contract schemaVersion: ${contract.schemaVersion}`);
  }
  if (!Array.isArray(contract.assets)) {
    fail("release asset contract assets must be an array");
  }
  if (contract.assets.length === 0) {
    fail("release asset contract must define at least one asset");
  }
  const keys = contract.assets.map((asset, index) => {
    exactKeys(asset, assetFields, `release asset ${index}`);
    if (typeof asset.key !== "string" || !/^[a-z][A-Za-z0-9]*$/.test(asset.key)) {
      fail(`release asset ${index} has an invalid key`);
    }
    validateTemplate(asset.name, ["version"], `${asset.key} name`);
    validateTemplate(asset.label, ["version"], `${asset.key} label`);
    validateTemplate(asset.sourcePath, ["version", "name"], `${asset.key} sourcePath`);
    if (typeof asset.contentType !== "string" || !/^[a-z0-9.+-]+\/[a-z0-9.+-]+$/.test(asset.contentType)) {
      fail(`${asset.key} has an invalid contentType`);
    }
    return asset.key;
  });
  if (new Set(keys).size !== keys.length) {
    fail("release asset keys must be unique");
  }
  return contract;
}

export function readReleaseAssetContract(filePath = contractPath) {
  let contract;
  try {
    contract = JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(`cannot read release asset contract: ${error.message}`);
  }
  return validateReleaseAssetContract(contract);
}

export function releaseAssets(version, contract = readReleaseAssetContract()) {
  if (!stableVersionPattern.test(version)) {
    fail("version must be a stable semantic version");
  }
  if (version.split(".").some((part) => !Number.isSafeInteger(Number(part)))) {
    fail("version exceeds the safe integer range");
  }
  validateReleaseAssetContract(contract);
  const assets = contract.assets.map((asset) => {
    const name = renderTemplate(asset.name, { version });
    if (name !== path.basename(name) || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) {
      fail(`${asset.key} renders an unsafe asset name`);
    }
    const sourcePath = renderTemplate(asset.sourcePath, { version, name });
    if (path.isAbsolute(sourcePath) || sourcePath.split(/[\\/]/).includes("..") || path.basename(sourcePath) !== name) {
      fail(`${asset.key} renders an unsafe or mismatched sourcePath`);
    }
    return {
      key: asset.key,
      name,
      label: renderTemplate(asset.label, { version }),
      contentType: asset.contentType,
      sourcePath,
    };
  });
  const names = assets.map((asset) => asset.name);
  if (new Set(names).size !== names.length) {
    fail("rendered release asset names must be unique");
  }
  return assets;
}

export function releaseAsset(version, key, contract = readReleaseAssetContract()) {
  const asset = releaseAssets(version, contract).find((candidate) => candidate.key === key);
  if (!asset) {
    fail(`unknown release asset key: ${key}`);
  }
  return asset;
}

export function releaseAssetNames(version, contract = readReleaseAssetContract()) {
  return releaseAssets(version, contract).map((asset) => asset.name);
}

export function validateReleaseAssetSet(actualAssets, version, contract = readReleaseAssetContract()) {
  if (!Array.isArray(actualAssets)) {
    fail("release asset set must be an array");
  }
  const expected = releaseAssets(version, contract).map(({ name, label, contentType }) => ({
    name,
    label,
    contentType,
  }));
  const normalized = actualAssets.map((asset, index) => {
    exactKeys(asset, ["name", "label", "contentType"], `release asset set entry ${index}`);
    return asset;
  });
  const byName = (left, right) => left.name.localeCompare(right.name, "en");
  if (JSON.stringify([...normalized].sort(byName)) !== JSON.stringify([...expected].sort(byName))) {
    fail("release asset set does not exactly match the contract");
  }
  return actualAssets;
}

function parseArgs(argv) {
  const [command, ...tokens] = argv;
  const options = {};
  for (let index = 0; index < tokens.length; index += 2) {
    const name = tokens[index];
    const value = tokens[index + 1];
    if (!name?.startsWith("--") || value === undefined) {
      fail(`invalid argument: ${name ?? ""}`);
    }
    const key = name.slice(2);
    if (Object.hasOwn(options, key)) {
      fail(`duplicate option: --${key}`);
    }
    options[key] = value;
  }
  const allowed = command === "field" ? ["version", "key", "field"] : ["version"];
  const unknown = Object.keys(options).filter((name) => !allowed.includes(name));
  if (unknown.length > 0) {
    fail(`unknown option: --${unknown[0]}`);
  }
  if (!options.version) {
    fail("--version is required");
  }
  return { command, options };
}

function main(argv) {
  const { command, options } = parseArgs(argv);
  const { version } = options;
  const assets = releaseAssets(version);
  if (command === "json") {
    process.stdout.write(`${JSON.stringify({ schemaVersion: 1, version, assets }, null, 2)}\n`);
  } else if (command === "names") {
    process.stdout.write(`${assets.map((asset) => asset.name).join("\n")}\n`);
  } else if (command === "field") {
    if (!options.key || !options.field) {
      fail("field requires --key and --field");
    }
    const asset = releaseAsset(version, options.key);
    if (!Object.hasOwn(asset, options.field)) {
      fail(`unknown release asset field: ${options.field}`);
    }
    process.stdout.write(`${asset[options.field]}\n`);
  } else {
    fail("usage: release-assets.mjs json|names|field --version VERSION [--key KEY --field FIELD]");
  }
}

const invokedPath = process.argv[1] ? fs.realpathSync(process.argv[1]) : "";
if (invokedPath === fs.realpathSync(fileURLToPath(import.meta.url))) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
