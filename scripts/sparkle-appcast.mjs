#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const stableVersionPattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const systemVersionPattern = /^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){1,2}$/;
const repositoryPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

function fail(message) {
  throw new Error(message);
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
  return { command, options };
}

function required(options, name) {
  const value = options[name];
  if (!value) {
    fail(`--${name} is required`);
  }
  return value;
}

function publicKeyFromBase64(encodedKey) {
  const rawKey = Buffer.from(encodedKey, "base64");
  if (rawKey.length !== 32 || rawKey.toString("base64") !== encodedKey) {
    fail("public key must be a canonical base64-encoded Ed25519 key");
  }
  const ed25519SubjectPublicKeyInfoPrefix = Buffer.from("302a300506032b6570032100", "hex");
  return crypto.createPublicKey({
    key: Buffer.concat([ed25519SubjectPublicKeyInfoPrefix, rawKey]),
    format: "der",
    type: "spki",
  });
}

function xpath(filePath, expression) {
  const result = spawnSync("/usr/bin/xmllint", ["--xpath", expression, filePath], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail(`cannot evaluate appcast XPath: ${result.stderr.trim()}`);
  }
  return result.stdout;
}

function xpathString(filePath, expression) {
  return xpath(filePath, `string(${expression})`).trim();
}

function compareStableVersions(left, right) {
  const leftParts = left.split(".").map(BigInt);
  const rightParts = right.split(".").map(BigInt);
  for (let index = 0; index < leftParts.length; index += 1) {
    if (leftParts[index] !== rightParts[index]) {
      return leftParts[index] < rightParts[index] ? -1 : 1;
    }
  }
  return 0;
}

export function validateAppcast({ file, archive, version, build, repository, publicKey }) {
  if (!stableVersionPattern.test(version)) {
    fail("version must be a stable semantic version");
  }
  if (!/^[1-9][0-9]*$/.test(build)) {
    fail("build must be a positive integer");
  }
  if (!repositoryPattern.test(repository)) {
    fail("repository must use OWNER/REPOSITORY form");
  }

  const filePath = path.resolve(file);
  const archivePath = path.resolve(archive);
  const { appcastText } = verifySignedAppcast({ filePath, publicKey });
  validateXML(filePath);

  const items = "/*[local-name()='rss']/*[local-name()='channel']/*[local-name()='item']";
  const itemCount = Number(xpathString(filePath, `count(${items})`));
  if (!Number.isInteger(itemCount) || itemCount < 1 || itemCount > 3) {
    fail("appcast must contain between one and three update items");
  }
  if (xpathString(filePath, `count(${items}/*[local-name()='enclosure'])`) !== String(itemCount)) {
    fail("every appcast update item must contain exactly one enclosure");
  }

  const seenVersions = new Set();
  const seenBuilds = new Set();
  for (let index = 1; index <= itemCount; index += 1) {
    const item = `(${items})[${index}]`;
    const enclosure = `${item}/*[local-name()='enclosure']`;
    const itemVersion = xpathString(
      filePath,
      `(${item}/*[local-name()='shortVersionString'] | ${enclosure}/@*[local-name()='shortVersionString'])[1]`,
    );
    const itemBuild = xpathString(
      filePath,
      `(${item}/*[local-name()='version'] | ${enclosure}/@*[local-name()='version'])[1]`,
    );
    const itemURL = xpathString(filePath, `${enclosure}/@url`);
    const itemLength = xpathString(filePath, `${enclosure}/@length`);
    const itemSignature = xpathString(filePath, `${enclosure}/@*[local-name()='edSignature']`);
    const itemLink = xpathString(filePath, `${item}/*[local-name()='link']`);
    const itemNotes = xpathString(filePath, `${item}/*[local-name()='description']`);
    const minimumSystemVersion = xpathString(
      filePath,
      `${item}/*[local-name()='minimumSystemVersion']`,
    );
    const hardwareRequirements = xpathString(
      filePath,
      `${item}/*[local-name()='hardwareRequirements']`,
    );
    const channel = xpathString(filePath, `${item}/*[local-name()='channel']`);
    const itemFullNotesURL = xpathString(
      filePath,
      `${item}/*[local-name()='fullReleaseNotesLink']`,
    );
    const expectedArchiveName = `md2png-${itemVersion}-macOS-arm64-developer-id.zip`;
    const expectedItemURL = `https://github.com/${repository}/releases/download/v${itemVersion}/${expectedArchiveName}`;

    if (!stableVersionPattern.test(itemVersion) || !/^[1-9][0-9]*$/.test(itemBuild)) {
      fail("appcast contains an invalid version or build number");
    }
    if (compareStableVersions(itemVersion, version) > 0 || BigInt(itemBuild) > BigInt(build)) {
      fail("appcast contains a version or build newer than the current release");
    }
    if (seenVersions.has(itemVersion) || seenBuilds.has(itemBuild)) {
      fail("appcast contains a duplicate version or build number");
    }
    seenVersions.add(itemVersion);
    seenBuilds.add(itemBuild);
    if (itemURL !== expectedItemURL) {
      fail("appcast contains a non-immutable or unexpected enclosure URL");
    }
    if (!/^[1-9][0-9]*$/.test(itemLength) || !/^[A-Za-z0-9+/]{86}==$/.test(itemSignature)) {
      fail("appcast enclosure is missing valid size or EdDSA metadata");
    }
    if (itemLink !== `https://github.com/${repository}/releases/tag/v${itemVersion}`) {
      fail("appcast release link does not match its version");
    }
    if (!itemNotes.trim()) {
      fail("every appcast item must embed non-empty release notes");
    }
    if (!systemVersionPattern.test(minimumSystemVersion) || hardwareRequirements !== "arm64") {
      fail("appcast contains missing or unsupported compatibility metadata");
    }
    if (channel) {
      fail("stable appcast items must not declare an update channel");
    }
    if (itemFullNotesURL && itemFullNotesURL !== `https://github.com/${repository}/releases`) {
      fail("appcast full release notes link is invalid");
    }
  }

  const currentItem = `(${items}[` +
    `*[local-name()='shortVersionString']='${version}' or ` +
    `*[local-name()='enclosure']/@*[local-name()='shortVersionString']='${version}'` +
    "])";
  if (xpathString(filePath, `count(${currentItem})`) !== "1") {
    fail("appcast must contain exactly one item for the current release");
  }
  const enclosure = `${currentItem}/*[local-name()='enclosure']`;
  const archiveName = path.basename(archivePath);
  const expectedURL = `https://github.com/${repository}/releases/download/v${version}/${archiveName}`;
  const expectedLink = `https://github.com/${repository}/releases/tag/v${version}`;
  const archiveData = fs.readFileSync(archivePath);
  const enclosureSignature = xpathString(
    filePath,
    `${enclosure}/@*[local-name()='edSignature']`,
  );
  const checks = [
    [xpathString(filePath, `${enclosure}/@url`), expectedURL, "enclosure URL"],
    [xpathString(filePath, `${enclosure}/@length`), String(archiveData.length), "archive length"],
    [xpathString(
      filePath,
      `(${currentItem}/*[local-name()='version'] | ${enclosure}/@*[local-name()='version'])[1]`,
    ), build, "build number"],
    [xpathString(filePath, `${currentItem}/*[local-name()='link']`), expectedLink, "release link"],
  ];
  for (const [actual, expected, label] of checks) {
    if (actual !== expected) {
      fail(`appcast ${label} does not match the release`);
    }
  }
  const verificationKey = publicKeyFromBase64(publicKey);
  if (!crypto.verify(
    null,
    archiveData,
    verificationKey,
    Buffer.from(enclosureSignature, "base64"),
  )) {
    fail("appcast enclosure signature does not verify the release ZIP");
  }
  const appcastWithoutSparkleNamespace = appcastText.replaceAll(
    "http://www.andymatuschak.org/xml-namespaces/sparkle",
    "",
  );
  if (appcastText.includes("sparkle:dsaSignature") || appcastWithoutSparkleNamespace.includes("http://")) {
    fail("appcast contains a legacy signature or insecure URL");
  }
  return true;
}

function verifySignedAppcast({ filePath, publicKey }) {
  const appcastData = fs.readFileSync(filePath);
  const appcastText = appcastData.toString("utf8");
  const signaturePattern = /<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]{86}==)\nlength: ([1-9][0-9]*)\n-->\n?$/;
  const signatureMatch = signaturePattern.exec(appcastText);
  if (!signatureMatch) {
    fail("appcast is missing its Sparkle feed signature block");
  }
  const signedContent = appcastData.subarray(0, Buffer.byteLength(
    appcastText.slice(0, signatureMatch.index),
    "utf8",
  ));
  if (Number(signatureMatch[2]) !== signedContent.length) {
    fail("appcast signed content length is incorrect");
  }
  const verificationKey = publicKeyFromBase64(publicKey);
  if (!crypto.verify(null, signedContent, verificationKey, Buffer.from(signatureMatch[1], "base64"))) {
    fail("appcast feed signature is invalid");
  }
  return { appcastText };
}

function validateXML(filePath) {
  const xmlCheck = spawnSync("/usr/bin/xmllint", ["--noout", filePath], { encoding: "utf8" });
  if (xmlCheck.status !== 0) {
    fail(`appcast is not well-formed XML: ${xmlCheck.stderr.trim()}`);
  }
}

export function validateSignedAppcast({ file, publicKey }) {
  const filePath = path.resolve(file);
  verifySignedAppcast({ filePath, publicKey });
  validateXML(filePath);
  return true;
}

function main(argv) {
  const { command, options } = parseArgs(argv);
  if (command !== "validate" && command !== "validate-feed") {
    fail("usage: sparkle-appcast.mjs validate|validate-feed [options]");
  }
  const allowed = command === "validate"
    ? ["file", "archive", "version", "build", "repository", "public-key"]
    : ["file", "public-key"];
  const unknown = Object.keys(options).find((name) => !allowed.includes(name));
  if (unknown) {
    fail(`unknown option: --${unknown}`);
  }
  if (command === "validate-feed") {
    validateSignedAppcast({
      file: required(options, "file"),
      publicKey: required(options, "public-key"),
    });
    process.stdout.write("Appcast feed signature is valid.\n");
  } else {
    validateAppcast({
      file: required(options, "file"),
      archive: required(options, "archive"),
      version: required(options, "version"),
      build: required(options, "build"),
      repository: required(options, "repository"),
      publicKey: required(options, "public-key"),
    });
    process.stdout.write("Appcast feed and archive signatures are valid.\n");
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
