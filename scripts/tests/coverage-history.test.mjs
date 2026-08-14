import assert from "node:assert/strict";
import test from "node:test";

import {
  buildHistorySection,
  HISTORY_END_MARKER,
  HISTORY_ISSUE_NUMBER,
  HISTORY_START_MARKER,
  replaceGeneratedSection,
  validateHistoryIssue,
} from "../coverage-history.mjs";

function report(version, commit, coveredLines, coverableLines) {
  const percentage = Math.round((coveredLines / coverableLines) * 10_000) / 100;
  return {
    schemaVersion: 1,
    metric: "source-line-coverage",
    sourcePattern: "Sources/MD2PNG/**/*.swift",
    appVersion: version,
    commit,
    toolchain: {
      swift: "Apple Swift version 6.2",
      xcode: "Xcode 26.2 (Build 17C52)",
    },
    totals: { coveredLines, coverableLines, percentage },
    files: [{
      path: "Sources/MD2PNG/AppDelegate.swift",
      coveredLines,
      coverableLines,
      percentage,
    }],
  };
}

test("renders two fixture releases in semantic-version order", () => {
  const section = buildHistorySection([
    {
      tag: "v0.10.0",
      tagCommit: "b".repeat(40),
      releaseDate: "2026-08-20",
      releaseUrl: "https://github.com/example/md2png/releases/tag/v0.10.0",
      report: report("0.10.0", "b".repeat(40), 7, 10),
    },
    {
      tag: "v0.3.0",
      tagCommit: "a".repeat(40),
      releaseDate: "2026-08-10",
      releaseUrl: "https://github.com/example/md2png/releases/tag/v0.3.0",
      report: report("0.3.0", "a".repeat(40), 6, 10),
    },
  ], [], { repository: "example/md2png" });

  assert.ok(section.indexOf("v0.3.0") < section.indexOf("v0.10.0"));
  assert.match(section, /x-axis \["v0\.3\.0", "v0\.10\.0"\]/);
  assert.match(section, /line \[60\.00, 70\.00\]/);
  assert.match(section, /\| \+10\.00 pp \|/);
  assert.match(section, /Covered \/ total lines/);
  assert.match(section, /\[`aaaaaaa`\]/);
});

test("keeps an accessible table and warnings when no chart data is valid", () => {
  const section = buildHistorySection([], [
    "`v0.2.0`: missing snapshot.",
    "`v0.1.0`: malformed snapshot.",
  ]);

  assert.match(section, /No valid coverage snapshots are available yet/);
  assert.match(section, /### Snapshot warnings/);
  assert.ok(section.indexOf("v0.1.0") < section.indexOf("v0.2.0"));
});

test("replaces only the generated section and preserves hand-written text", () => {
  const original = [
    "# Test coverage history",
    "",
    "Hand-written explanation.",
    "",
    HISTORY_START_MARKER,
    "old generated content",
    HISTORY_END_MARKER,
    "",
    "Hand-written footer.",
  ].join("\n");
  const generated = `${HISTORY_START_MARKER}\nnew generated content\n${HISTORY_END_MARKER}`;
  const updated = replaceGeneratedSection(original, generated);

  assert.match(updated, /^# Test coverage history/);
  assert.match(updated, /Hand-written explanation/);
  assert.match(updated, /new generated content/);
  assert.match(updated, /Hand-written footer\.$/);
  assert.equal(updated.includes("old generated content"), false);
  assert.equal(replaceGeneratedSection(updated, generated), updated);
});

test("refuses to edit an issue without exactly one marker pair", () => {
  assert.throws(
    () => replaceGeneratedSection("# Missing markers", "generated"),
    /missing valid generated-section markers/,
  );
  assert.throws(
    () => replaceGeneratedSection(
      `${HISTORY_START_MARKER}\n${HISTORY_END_MARKER}\n${HISTORY_END_MARKER}`,
      "generated",
    ),
    /duplicate generated-section markers/,
  );
});

test("rejects report and release version mismatches", () => {
  assert.throws(
    () => buildHistorySection([{
      tag: "v0.4.0",
      tagCommit: "a".repeat(40),
      releaseDate: "2026-08-20",
      releaseUrl: "https://example.com/release",
      report: report("0.3.0", "a".repeat(40), 6, 10),
    }], []),
    /does not match 0\.4\.0/,
  );
});

test("rejects a report whose commit differs from its release tag", () => {
  assert.throws(
    () => buildHistorySection([{
      tag: "v0.3.0",
      tagCommit: "b".repeat(40),
      releaseDate: "2026-08-20",
      releaseUrl: "https://example.com/release",
      report: report("0.3.0", "a".repeat(40), 6, 10),
    }], []),
    /report commit does not match its release tag/,
  );
});

test("targets issue 42 regardless of title or open state", () => {
  const issue = {
    number: HISTORY_ISSUE_NUMBER,
    title: "Renamed coverage dashboard",
    state: "closed",
    body: `${HISTORY_START_MARKER}\n${HISTORY_END_MARKER}`,
  };

  assert.equal(validateHistoryIssue(issue), issue);
});

test("rejects the wrong issue number and pull request targets", () => {
  assert.throws(
    () => validateHistoryIssue({ number: 41, body: "body" }),
    /issue number must be 42/,
  );
  assert.throws(
    () => validateHistoryIssue({
      number: HISTORY_ISSUE_NUMBER,
      body: "body",
      pull_request: { url: "https://api.github.com/example" },
    }),
    /must be an issue, not a pull request/,
  );
});
