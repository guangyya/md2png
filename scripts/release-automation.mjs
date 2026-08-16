#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { releaseAssetNames } from "./release-assets.mjs";

export const RELEASE_FILES = ["Info.plist", "CHANGELOG.md", "ABOUT_CHANGELOG.md"];
export const BUMP_TYPES = ["patch", "minor", "major"];

const stableVersionPattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const releaseHeadingPattern = /^## \[([^\]]+)\](?: - (\d{4}-\d{2}-\d{2}))?[ \t]*$/gm;
const allowedChangeHeadingPattern = /^### (Added|Changed|Deprecated|Removed|Fixed|Security)[ \t]*$/m;

function fail(message) {
  throw new Error(message);
}

function normalizeNewlines(value) {
  return value.replace(/\r\n?/g, "\n");
}

function parsePositiveInteger(value, label) {
  if (!/^[1-9][0-9]*$/.test(value)) {
    fail(`${label} must be a positive integer`);
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    fail(`${label} exceeds the safe integer range`);
  }
  return parsed;
}

export function parseStableVersion(value, label = "version") {
  const match = stableVersionPattern.exec(value);
  if (!match) {
    fail(`${label} must be a stable semantic version`);
  }
  const parts = match.slice(1).map((part) => Number(part));
  if (parts.some((part) => !Number.isSafeInteger(part))) {
    fail(`${label} exceeds the safe integer range`);
  }
  return parts;
}

export function nextVersion(version, bump) {
  if (!BUMP_TYPES.includes(bump)) {
    fail(`bump must be one of: ${BUMP_TYPES.join(", ")}`);
  }
  let [major, minor, patch] = parseStableVersion(version);
  if (bump === "major") {
    major += 1;
    minor = 0;
    patch = 0;
  } else if (bump === "minor") {
    minor += 1;
    patch = 0;
  } else {
    patch += 1;
  }
  if (![major, minor, patch].every(Number.isSafeInteger)) {
    fail("next version exceeds the safe integer range");
  }
  return `${major}.${minor}.${patch}`;
}

export function deriveBump(oldVersion, newVersion) {
  parseStableVersion(oldVersion, "old version");
  parseStableVersion(newVersion, "new version");
  const bump = BUMP_TYPES.find((candidate) => nextVersion(oldVersion, candidate) === newVersion);
  if (!bump) {
    fail(`${newVersion} is not an exact patch, minor, or major bump from ${oldVersion}`);
  }
  return bump;
}

function plistString(content, key) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`<key>${escapedKey}</key>\\s*<string>([^<]*)</string>`, "g");
  const matches = [...content.matchAll(pattern)];
  if (matches.length !== 1) {
    fail(`Info.plist must contain exactly one ${key} string`);
  }
  return matches[0][1];
}

function replacePlistString(content, key, value) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`(<key>${escapedKey}</key>\\s*<string>)([^<]*)(</string>)`, "g");
  const matches = [...content.matchAll(pattern)];
  if (matches.length !== 1) {
    fail(`Info.plist must contain exactly one ${key} string`);
  }
  return content.replace(pattern, `$1${value}$3`);
}

export function parsePlistMetadata(content) {
  const version = plistString(content, "CFBundleShortVersionString");
  parseStableVersion(version, "CFBundleShortVersionString");
  const buildText = plistString(content, "CFBundleVersion");
  const build = parsePositiveInteger(buildText, "CFBundleVersion");
  return { version, build };
}

function changelogSections(content, label) {
  const normalized = normalizeNewlines(content);
  const matches = [...normalized.matchAll(releaseHeadingPattern)].map((match) => ({
    name: match[1],
    date: match[2] ?? null,
    headingStart: match.index,
    contentStart: match.index + match[0].length,
  }));
  if (matches.length === 0) {
    fail(`${label} has no version headings`);
  }
  return matches.map((section, index) => ({
    ...section,
    content: normalized.slice(
      section.contentStart,
      index + 1 < matches.length ? matches[index + 1].headingStart : normalized.length,
    ).trim(),
    end: index + 1 < matches.length ? matches[index + 1].headingStart : normalized.length,
  }));
}

function exactlyOneSection(content, name, label) {
  const matches = changelogSections(content, label).filter((section) => section.name === name);
  if (matches.length !== 1) {
    fail(`${label} must contain exactly one [${name}] section`);
  }
  return matches[0];
}

function validateReleaseContent(content, label) {
  if (!content.trim()) {
    fail(`${label} is empty`);
  }
  if (!allowedChangeHeadingPattern.test(content)) {
    fail(`${label} must contain a Keep a Changelog category heading`);
  }
  if (!/^- \S.*$/m.test(content)) {
    fail(`${label} must contain at least one nonempty bullet`);
  }
  if (/\b(?:TBD|TODO|YYYY-MM-DD)\b/i.test(content)) {
    fail(`${label} contains a placeholder`);
  }
}

function validateDate(date) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    fail("release date must use YYYY-MM-DD");
  }
  const parsed = new Date(`${date}T00:00:00Z`);
  if (Number.isNaN(parsed.valueOf()) || parsed.toISOString().slice(0, 10) !== date) {
    fail("release date is invalid");
  }
}

export function releaseDateForInstant(value) {
  const instant = new Date(value);
  if (Number.isNaN(instant.valueOf())) {
    fail("release instant is invalid");
  }
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "Asia/Shanghai",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(instant).map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function prepareChangelog(content, targetVersion, date, label) {
  const normalized = normalizeNewlines(content);
  if (changelogSections(normalized, label)[0].name !== "Unreleased") {
    fail(`${label} [Unreleased] must be the first version section`);
  }
  const unreleased = exactlyOneSection(normalized, "Unreleased", label);
  if (unreleased.date !== null) {
    fail(`${label} [Unreleased] must not have a date`);
  }
  validateReleaseContent(unreleased.content, `${label} [Unreleased]`);
  if (changelogSections(normalized, label).some((section) => section.name === targetVersion)) {
    fail(`${label} already contains [${targetVersion}]`);
  }
  const prefix = normalized.slice(0, unreleased.headingStart);
  const suffix = normalized.slice(unreleased.end).replace(/^\s*/, "");
  return `${prefix}## [Unreleased]\n\n## [${targetVersion}] - ${date}\n\n${unreleased.content}\n\n${suffix}`;
}

function releasePlan(oldVersion, oldBuild, bump, date) {
  const version = nextVersion(oldVersion, bump);
  const build = oldBuild + 1;
  if (!Number.isSafeInteger(build)) {
    fail("next build number exceeds the safe integer range");
  }
  return {
    bump,
    date,
    oldVersion,
    version,
    oldBuild,
    build,
    tag: `v${version}`,
    branch: `codex/release-v${version}`,
    title: `Prepare md2png ${version}`,
    commitTitle: `Prepare md2png ${version}`,
    releaseTitle: `md2png ${version}`,
    artifacts: releaseAssetNames(version),
  };
}

function readReleaseFiles(repoRoot) {
  return Object.fromEntries(RELEASE_FILES.map((name) => [
    name,
    fs.readFileSync(path.join(repoRoot, name), "utf8"),
  ]));
}

export function inspectRelease(repoRoot) {
  const files = readReleaseFiles(repoRoot);
  const metadata = parsePlistMetadata(files["Info.plist"]);
  const changelog = exactlyOneSection(files["CHANGELOG.md"], "Unreleased", "CHANGELOG.md");
  const about = exactlyOneSection(files["ABOUT_CHANGELOG.md"], "Unreleased", "ABOUT_CHANGELOG.md");
  return {
    ...metadata,
    changelogUnreleased: changelog.content,
    aboutUnreleased: about.content,
  };
}

export function planRelease({ repoRoot, bump, date }) {
  validateDate(date);
  const files = readReleaseFiles(repoRoot);
  const { version: oldVersion, build: oldBuild } = parsePlistMetadata(files["Info.plist"]);
  const plan = releasePlan(oldVersion, oldBuild, bump, date);
  prepareChangelog(files["CHANGELOG.md"], plan.version, date, "CHANGELOG.md");
  prepareChangelog(files["ABOUT_CHANGELOG.md"], plan.version, date, "ABOUT_CHANGELOG.md");
  return plan;
}

export function prepareRelease({ repoRoot, bump, date }) {
  const files = readReleaseFiles(repoRoot);
  const plan = planRelease({ repoRoot, bump, date });
  const updated = {
    "Info.plist": replacePlistString(
      replacePlistString(files["Info.plist"], "CFBundleShortVersionString", plan.version),
      "CFBundleVersion",
      String(plan.build),
    ),
    "CHANGELOG.md": prepareChangelog(files["CHANGELOG.md"], plan.version, date, "CHANGELOG.md"),
    "ABOUT_CHANGELOG.md": prepareChangelog(
      files["ABOUT_CHANGELOG.md"],
      plan.version,
      date,
      "ABOUT_CHANGELOG.md",
    ),
  };
  for (const name of RELEASE_FILES) {
    fs.writeFileSync(path.join(repoRoot, name), updated[name]);
  }
  return plan;
}

function normalizedSectionContent(content) {
  return normalizeNewlines(content).trim();
}

export function validatePreparedRelease({ baseRoot, repoRoot, bump = null }) {
  const baseFiles = readReleaseFiles(baseRoot);
  const currentFiles = readReleaseFiles(repoRoot);
  const baseMetadata = parsePlistMetadata(baseFiles["Info.plist"]);
  const currentMetadata = parsePlistMetadata(currentFiles["Info.plist"]);
  const derivedBump = deriveBump(baseMetadata.version, currentMetadata.version);
  if (bump !== null && bump !== derivedBump) {
    fail(`prepared bump is ${derivedBump}, expected ${bump}`);
  }
  const expectedVersion = nextVersion(baseMetadata.version, derivedBump);
  if (currentMetadata.version !== expectedVersion) {
    fail(`prepared version is ${currentMetadata.version}, expected ${expectedVersion}`);
  }
  if (currentMetadata.build !== baseMetadata.build + 1) {
    fail(`prepared build is ${currentMetadata.build}, expected ${baseMetadata.build + 1}`);
  }
  const expectedPlist = replacePlistString(
    replacePlistString(baseFiles["Info.plist"], "CFBundleShortVersionString", expectedVersion),
    "CFBundleVersion",
    String(currentMetadata.build),
  );
  if (currentFiles["Info.plist"] !== expectedPlist) {
    fail("Info.plist may change only the two release version values");
  }

  let releaseDate = null;
  for (const name of ["CHANGELOG.md", "ABOUT_CHANGELOG.md"]) {
    const baseUnreleased = exactlyOneSection(baseFiles[name], "Unreleased", name);
    validateReleaseContent(baseUnreleased.content, `base ${name} [Unreleased]`);
    const currentUnreleased = exactlyOneSection(currentFiles[name], "Unreleased", name);
    if (currentUnreleased.date !== null || currentUnreleased.content !== "") {
      fail(`${name} must recreate an empty undated [Unreleased] section`);
    }
    const prepared = exactlyOneSection(currentFiles[name], expectedVersion, name);
    if (prepared.date === null) {
      fail(`${name} [${expectedVersion}] must have a release date`);
    }
    validateDate(prepared.date);
    validateReleaseContent(prepared.content, `${name} [${expectedVersion}]`);
    if (normalizedSectionContent(prepared.content) !== normalizedSectionContent(baseUnreleased.content)) {
      fail(`${name} [${expectedVersion}] must exactly match the base [Unreleased] content`);
    }
    if (releaseDate !== null && releaseDate !== prepared.date) {
      fail("CHANGELOG.md and ABOUT_CHANGELOG.md release dates must match");
    }
    releaseDate = prepared.date;
    const expectedDocument = prepareChangelog(baseFiles[name], expectedVersion, releaseDate, name);
    if (normalizeNewlines(currentFiles[name]) !== expectedDocument) {
      fail(`${name} contains changes outside the deterministic release transformation`);
    }
  }

  return releasePlan(baseMetadata.version, baseMetadata.build, derivedBump, releaseDate);
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
    if (Object.hasOwn(options, name)) {
      fail(`duplicate option: --${name}`);
    }
    options[name] = tokens[index + 1];
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

function requiredOption(options, name) {
  const value = options[name];
  if (!value) {
    fail(`--${name} is required`);
  }
  return value;
}

function main(argv) {
  const { command, options } = parseArgs(argv);
  const repoRoot = path.resolve(options["repo-root"] ?? process.cwd());
  let result;
  if (command === "date") {
    allowOnlyOptions(options, ["instant"]);
    result = { date: releaseDateForInstant(requiredOption(options, "instant")) };
  } else if (command === "inspect") {
    allowOnlyOptions(options, ["repo-root"]);
    result = inspectRelease(repoRoot);
  } else if (command === "plan") {
    allowOnlyOptions(options, ["repo-root", "bump", "date"]);
    result = planRelease({
      repoRoot,
      bump: requiredOption(options, "bump"),
      date: requiredOption(options, "date"),
    });
  } else if (command === "prepare") {
    allowOnlyOptions(options, ["repo-root", "bump", "date"]);
    result = prepareRelease({
      repoRoot,
      bump: requiredOption(options, "bump"),
      date: requiredOption(options, "date"),
    });
  } else if (command === "validate-prepared") {
    allowOnlyOptions(options, ["repo-root", "base-root", "bump"]);
    result = validatePreparedRelease({
      repoRoot,
      baseRoot: path.resolve(requiredOption(options, "base-root")),
      bump: options.bump ?? null,
    });
  } else {
    fail("usage: release-automation.mjs date|inspect|plan|prepare|validate-prepared [options]");
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
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
