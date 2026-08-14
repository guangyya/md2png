import assert from "node:assert/strict";
import test from "node:test";

import {
  coverageMarkdown,
  coveragePercentage,
  createCoverageReport,
  normalizeSourcePath,
  parseArguments,
  validateCoverageReport,
} from "../coverage-report.mjs";

const repoRoot = "/Users/example/md2png";
const metadata = {
  appVersion: "0.3.0",
  commit: "0123456789abcdef0123456789abcdef01234567",
  swiftVersion: "Apple Swift version 6.2",
  xcodeVersion: "Xcode 26.2 (Build 17C52)",
  repoRoot,
};

function llvmFile(filename, covered, count) {
  return {
    filename,
    summary: {
      lines: { covered, count, percent: count === 0 ? 0 : (covered / count) * 100 },
    },
  };
}

function llvmCoverage(files) {
  return {
    type: "llvm.coverage.json.export",
    version: "2.0.1",
    data: [{ files }],
  };
}

function sampleReport() {
  return createCoverageReport(
    llvmCoverage([
      llvmFile(`${repoRoot}/Sources/MD2PNG/Zebra.swift`, 1, 3),
      llvmFile(`${repoRoot}/Tests/MD2PNGTests/ZebraTests.swift`, 10, 10),
      llvmFile(`${repoRoot}/.build/debug/MD2PNG.build/DerivedSources/resource_bundle_accessor.swift`, 2, 2),
      llvmFile(`${repoRoot}/Sources/MD2PNG/AppDelegate.swift`, 2, 3),
    ]),
    metadata,
  );
}

test("normalizes only repository app source paths", () => {
  assert.equal(
    normalizeSourcePath(`${repoRoot}/Sources/MD2PNG/AppDelegate.swift`, repoRoot),
    "Sources/MD2PNG/AppDelegate.swift",
  );
  assert.equal(
    normalizeSourcePath("Sources/MD2PNG/Feature/Controller.swift", repoRoot),
    "Sources/MD2PNG/Feature/Controller.swift",
  );
  assert.equal(normalizeSourcePath(`${repoRoot}/Tests/Test.swift`, repoRoot), null);
  assert.equal(normalizeSourcePath(`${repoRoot}/.build/generated.swift`, repoRoot), null);
  assert.equal(normalizeSourcePath("../other/Sources/MD2PNG/Leaked.swift", repoRoot), null);
  assert.equal(normalizeSourcePath("Sources/Other/Dependency.swift", repoRoot), null);
});

test("filters sources, sorts paths, and calculates totals", () => {
  const report = sampleReport();

  assert.deepEqual(
    report.files.map((file) => file.path),
    ["Sources/MD2PNG/AppDelegate.swift", "Sources/MD2PNG/Zebra.swift"],
  );
  assert.deepEqual(report.totals, {
    coveredLines: 3,
    coverableLines: 6,
    percentage: 50,
  });
  assert.equal(JSON.stringify(report).includes(repoRoot), false);
});

test("rounds percentages to two decimal places", () => {
  assert.equal(coveragePercentage(2_392, 3_733), 64.08);
  assert.equal(coveragePercentage(1, 3), 33.33);
  assert.equal(coveragePercentage(2, 3), 66.67);
  assert.equal(coveragePercentage(0, 0), 0);
});

test("keeps zero-line source files without dividing by zero", () => {
  const report = createCoverageReport(
    llvmCoverage([llvmFile(`${repoRoot}/Sources/MD2PNG/Empty.swift`, 0, 0)]),
    metadata,
  );

  assert.equal(report.files[0].percentage, 0);
  assert.equal(report.totals.percentage, 0);
  assert.doesNotThrow(() => validateCoverageReport(report));
});

test("rejects incompatible LLVM schemas and empty measured source sets", () => {
  assert.throws(
    () => createCoverageReport({ ...llvmCoverage([]), version: "3.0.0" }, metadata),
    /unsupported LLVM coverage schema version/,
  );
  assert.throws(
    () => createCoverageReport(llvmCoverage([llvmFile(`${repoRoot}/Tests/Test.swift`, 1, 1)]), metadata),
    /contains no files matching/,
  );
});

test("rejects malformed and internally inconsistent normalized summaries", () => {
  const report = sampleReport();
  assert.doesNotThrow(() => validateCoverageReport(report, {
    appVersion: metadata.appVersion,
    commit: metadata.commit,
  }));
  assert.throws(
    () => validateCoverageReport({ ...report, schemaVersion: 2 }),
    /unsupported coverage report schemaVersion/,
  );
  assert.throws(
    () => validateCoverageReport({
      ...report,
      totals: { ...report.totals, coveredLines: report.totals.coveredLines + 1 },
    }),
    /percentage must equal|totals do not match/,
  );
  assert.throws(
    () => validateCoverageReport(report, { commit: "f".repeat(40) }),
    /does not match/,
  );
});

test("renders a compact per-file summary", () => {
  const report = sampleReport();
  const markdown = coverageMarkdown(report);

  assert.match(markdown, /Line coverage \| \*\*50\.00%\*\*/);
  assert.match(markdown, /Sources\/MD2PNG\/AppDelegate\.swift/);
  assert.equal(markdown.includes(repoRoot), false);
});

test("rejects unknown, duplicate, and incomplete command options", () => {
  assert.throws(
    () => parseArguments(["generate", "--baselien", "report.json"]),
    /unknown option/,
  );
  assert.throws(
    () => parseArguments(["validate", "--report", "one.json", "--report", "two.json"]),
    /duplicate option/,
  );
  assert.throws(
    () => parseArguments(["generate", "--input"]),
    /invalid argument/,
  );
});
