#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export const COVERAGE_SCHEMA_VERSION = 1;
export const COVERAGE_METRIC = "source-line-coverage";
export const COVERAGE_SOURCE_PATTERN = "Sources/MD2PNG/**/*.swift";

function fail(message) {
  throw new Error(message);
}

function assertNonEmptyString(value, name) {
  if (typeof value !== "string" || value.trim() === "") {
    fail(`${name} must be a non-empty string`);
  }
}

function assertLineCounts(value, name) {
  if (!value || typeof value !== "object") {
    fail(`${name} must be an object`);
  }
  const { coveredLines, coverableLines, percentage } = value;
  if (!Number.isInteger(coveredLines) || coveredLines < 0) {
    fail(`${name}.coveredLines must be a non-negative integer`);
  }
  if (!Number.isInteger(coverableLines) || coverableLines < 0) {
    fail(`${name}.coverableLines must be a non-negative integer`);
  }
  if (coveredLines > coverableLines) {
    fail(`${name}.coveredLines cannot exceed coverableLines`);
  }
  if (typeof percentage !== "number" || !Number.isFinite(percentage)) {
    fail(`${name}.percentage must be a finite number`);
  }
  const expectedPercentage = coveragePercentage(coveredLines, coverableLines);
  if (percentage !== expectedPercentage) {
    fail(`${name}.percentage must equal ${expectedPercentage}`);
  }
}

export function coveragePercentage(coveredLines, coverableLines) {
  if (!Number.isInteger(coveredLines) || !Number.isInteger(coverableLines)) {
    fail("coverage line counts must be integers");
  }
  if (coveredLines < 0 || coverableLines < 0 || coveredLines > coverableLines) {
    fail("coverage line counts are invalid");
  }
  if (coverableLines === 0) {
    return 0;
  }
  return Math.round((coveredLines / coverableLines) * 10_000) / 100;
}

export function normalizeSourcePath(filename, repoRoot) {
  assertNonEmptyString(filename, "coverage filename");
  assertNonEmptyString(repoRoot, "repository root");

  const normalizedRoot = path.resolve(repoRoot);
  const normalizedFilename = filename.replaceAll("\\", "/");
  const absoluteFilename = path.isAbsolute(normalizedFilename)
    ? path.resolve(normalizedFilename)
    : path.resolve(normalizedRoot, normalizedFilename);
  const relativePath = path.relative(normalizedRoot, absoluteFilename).replaceAll("\\", "/");

  if (relativePath === "" || relativePath === ".." || relativePath.startsWith("../")) {
    return null;
  }
  if (!/^Sources\/MD2PNG\/.+\.swift$/.test(relativePath)) {
    return null;
  }
  return relativePath;
}

function llvmLineCounts(file, index) {
  const lines = file?.summary?.lines;
  if (!lines || typeof lines !== "object") {
    fail(`LLVM coverage file ${index} is missing summary.lines`);
  }
  const coveredLines = lines.covered;
  const coverableLines = lines.count;
  if (!Number.isInteger(coveredLines) || !Number.isInteger(coverableLines)) {
    fail(`LLVM coverage file ${index} has non-integer line counts`);
  }
  if (coveredLines < 0 || coverableLines < 0 || coveredLines > coverableLines) {
    fail(`LLVM coverage file ${index} has invalid line counts`);
  }
  return {
    coveredLines,
    coverableLines,
    percentage: coveragePercentage(coveredLines, coverableLines),
  };
}

export function createCoverageReport(llvmCoverage, metadata) {
  if (!llvmCoverage || typeof llvmCoverage !== "object") {
    fail("LLVM coverage input must be an object");
  }
  if (llvmCoverage.type !== "llvm.coverage.json.export") {
    fail(`unsupported LLVM coverage type: ${String(llvmCoverage.type)}`);
  }
  if (typeof llvmCoverage.version !== "string" || !/^2\./.test(llvmCoverage.version)) {
    fail(`unsupported LLVM coverage schema version: ${String(llvmCoverage.version)}`);
  }
  if (!Array.isArray(llvmCoverage.data) || llvmCoverage.data.length !== 1) {
    fail("LLVM coverage input must contain exactly one data entry");
  }
  if (!Array.isArray(llvmCoverage.data[0].files)) {
    fail("LLVM coverage input is missing data[0].files");
  }

  const { appVersion, commit, swiftVersion, xcodeVersion, repoRoot } = metadata;
  assertNonEmptyString(appVersion, "app version");
  if (!/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(appVersion)) {
    fail("app version must be a stable semantic version");
  }
  assertNonEmptyString(commit, "commit");
  if (!/^[0-9a-f]{40}$/.test(commit)) {
    fail("commit must be a full lowercase Git SHA");
  }
  assertNonEmptyString(swiftVersion, "Swift version");
  assertNonEmptyString(xcodeVersion, "Xcode version");
  assertNonEmptyString(repoRoot, "repository root");

  const seenPaths = new Set();
  const files = [];
  for (const [index, file] of llvmCoverage.data[0].files.entries()) {
    const sourcePath = normalizeSourcePath(file?.filename, repoRoot);
    if (sourcePath === null) {
      continue;
    }
    if (seenPaths.has(sourcePath)) {
      fail(`LLVM coverage contains duplicate source path: ${sourcePath}`);
    }
    seenPaths.add(sourcePath);
    files.push({
      path: sourcePath,
      ...llvmLineCounts(file, index),
    });
  }

  if (files.length === 0) {
    fail(`LLVM coverage contains no files matching ${COVERAGE_SOURCE_PATTERN}`);
  }
  files.sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);

  const coveredLines = files.reduce((sum, file) => sum + file.coveredLines, 0);
  const coverableLines = files.reduce((sum, file) => sum + file.coverableLines, 0);
  return {
    schemaVersion: COVERAGE_SCHEMA_VERSION,
    metric: COVERAGE_METRIC,
    sourcePattern: COVERAGE_SOURCE_PATTERN,
    appVersion,
    commit,
    toolchain: {
      swift: swiftVersion.trim(),
      xcode: xcodeVersion.trim(),
    },
    totals: {
      coveredLines,
      coverableLines,
      percentage: coveragePercentage(coveredLines, coverableLines),
    },
    files,
  };
}

export function validateCoverageReport(report, expected = {}) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    fail("coverage report must be an object");
  }
  if (report.schemaVersion !== COVERAGE_SCHEMA_VERSION) {
    fail(`unsupported coverage report schemaVersion: ${String(report.schemaVersion)}`);
  }
  if (report.metric !== COVERAGE_METRIC) {
    fail(`unsupported coverage metric: ${String(report.metric)}`);
  }
  if (report.sourcePattern !== COVERAGE_SOURCE_PATTERN) {
    fail(`unsupported coverage sourcePattern: ${String(report.sourcePattern)}`);
  }
  assertNonEmptyString(report.appVersion, "report appVersion");
  if (!/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(report.appVersion)) {
    fail("report appVersion must be a stable semantic version");
  }
  assertNonEmptyString(report.commit, "report commit");
  if (!/^[0-9a-f]{40}$/.test(report.commit)) {
    fail("report commit must be a full lowercase Git SHA");
  }
  assertNonEmptyString(report?.toolchain?.swift, "report toolchain.swift");
  assertNonEmptyString(report?.toolchain?.xcode, "report toolchain.xcode");
  assertLineCounts(report.totals, "report totals");
  if (!Array.isArray(report.files) || report.files.length === 0) {
    fail("coverage report must contain at least one file");
  }

  let previousPath = "";
  let coveredLines = 0;
  let coverableLines = 0;
  for (const [index, file] of report.files.entries()) {
    assertNonEmptyString(file?.path, `report files[${index}].path`);
    if (!/^Sources\/MD2PNG\/.+\.swift$/.test(file.path) || path.posix.normalize(file.path) !== file.path) {
      fail(`report files[${index}].path is not a normalized app source path`);
    }
    if (previousPath !== "" && previousPath >= file.path) {
      fail("coverage report files must be uniquely sorted by path");
    }
    previousPath = file.path;
    assertLineCounts(file, `report files[${index}]`);
    coveredLines += file.coveredLines;
    coverableLines += file.coverableLines;
  }

  if (coveredLines !== report.totals.coveredLines || coverableLines !== report.totals.coverableLines) {
    fail("coverage report totals do not match the per-file counts");
  }
  if (expected.appVersion !== undefined && report.appVersion !== expected.appVersion) {
    fail(`coverage report version ${report.appVersion} does not match ${expected.appVersion}`);
  }
  if (expected.commit !== undefined && report.commit !== expected.commit) {
    fail(`coverage report commit ${report.commit} does not match ${expected.commit}`);
  }
  return report;
}

export function releaseVersionFromCoverageFilename(filename) {
  const match = /^md2png-((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))-coverage\.json$/
    .exec(path.basename(filename));
  if (match === null) {
    fail(`coverage baseline must use a versioned release filename: ${filename}`);
  }
  return match[1];
}

function markdownEscape(value) {
  return String(value).replaceAll("|", "\\|");
}

function signedPercentage(value) {
  return `${value >= 0 ? "+" : ""}${value.toFixed(2)} pp`;
}

export function coverageMarkdown(report, baseline = null) {
  validateCoverageReport(report);
  if (baseline !== null) {
    validateCoverageReport(baseline);
  }

  const lines = [
    "# Test coverage",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    `| App version | ${markdownEscape(report.appVersion)} |`,
    `| Commit | \`${report.commit}\` |`,
    `| Covered lines | ${report.totals.coveredLines.toLocaleString("en-US")} |`,
    `| Coverable lines | ${report.totals.coverableLines.toLocaleString("en-US")} |`,
    `| Line coverage | **${report.totals.percentage.toFixed(2)}%** |`,
  ];

  if (baseline !== null) {
    const delta = Math.round((report.totals.percentage - baseline.totals.percentage) * 100) / 100;
    lines.push(
      `| Latest release baseline | ${markdownEscape(baseline.appVersion)} (${baseline.totals.percentage.toFixed(2)}%) |`,
      `| Absolute delta | **${signedPercentage(delta)}** |`,
    );
  }

  lines.push(
    "",
    `Swift: ${report.toolchain.swift}  `,
    `Xcode: ${report.toolchain.xcode}`,
    "",
    "## Files",
    "",
    "| File | Covered | Coverable | Coverage |",
    "| --- | ---: | ---: | ---: |",
  );
  for (const file of report.files) {
    lines.push(
      `| \`${markdownEscape(file.path)}\` | ${file.coveredLines} | ${file.coverableLines} | ${file.percentage.toFixed(2)}% |`,
    );
  }
  lines.push("");
  return lines.join("\n");
}

export function parseArguments(argv) {
  const [command, ...rest] = argv;
  if (command !== "generate" && command !== "validate") {
    fail("usage: coverage-report.mjs <generate|validate> [options]");
  }
  const allowedOptions = new Set(command === "generate"
    ? ["input", "json", "markdown", "repo-root", "app-version", "commit", "swift-version", "xcode-version", "baseline"]
    : ["report", "app-version", "commit"]);
  const options = {};
  for (let index = 0; index < rest.length; index += 2) {
    const key = rest[index];
    const value = rest[index + 1];
    if (!key?.startsWith("--") || value === undefined) {
      fail(`invalid argument: ${String(key)}`);
    }
    const optionName = key.slice(2);
    if (!allowedOptions.has(optionName)) {
      fail(`unknown option for ${command}: ${key}`);
    }
    if (Object.hasOwn(options, optionName)) {
      fail(`duplicate option: ${key}`);
    }
    options[optionName] = value;
  }
  return { command, options };
}

function requiredOption(options, key) {
  const value = options[key];
  assertNonEmptyString(value, `--${key}`);
  return value;
}

function readJSON(filename, description) {
  try {
    return JSON.parse(fs.readFileSync(filename, "utf8"));
  } catch (error) {
    fail(`cannot read ${description} ${filename}: ${error.message}`);
  }
}

function writeFile(filename, contents) {
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, contents, "utf8");
}

function main(argv) {
  const { command, options } = parseArguments(argv);
  if (command === "validate") {
    const reportPath = requiredOption(options, "report");
    const report = readJSON(reportPath, "coverage report");
    validateCoverageReport(report, {
      appVersion: requiredOption(options, "app-version"),
      commit: requiredOption(options, "commit"),
    });
    process.stdout.write(`Validated ${reportPath}\n`);
    return;
  }

  const inputPath = requiredOption(options, "input");
  const jsonPath = requiredOption(options, "json");
  const markdownPath = requiredOption(options, "markdown");
  const report = createCoverageReport(readJSON(inputPath, "LLVM coverage input"), {
    appVersion: requiredOption(options, "app-version"),
    commit: requiredOption(options, "commit"),
    swiftVersion: requiredOption(options, "swift-version"),
    xcodeVersion: requiredOption(options, "xcode-version"),
    repoRoot: requiredOption(options, "repo-root"),
  });
  const baseline = options.baseline === undefined
    ? null
    : validateCoverageReport(readJSON(options.baseline, "coverage baseline"), {
      appVersion: releaseVersionFromCoverageFilename(options.baseline),
    });

  writeFile(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
  writeFile(markdownPath, coverageMarkdown(report, baseline));
  process.stdout.write(
    `Coverage: ${report.totals.coveredLines}/${report.totals.coverableLines} lines (${report.totals.percentage.toFixed(2)}%)\n`,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`coverage-report: ${error.message}\n`);
    process.exitCode = 1;
  }
}
