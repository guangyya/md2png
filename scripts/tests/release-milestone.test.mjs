import assert from "node:assert/strict";
import test from "node:test";

import {
  parseFirstParentLog,
  releaseMilestoneMarkdown,
  selectReleaseIssues,
  trackedIssueIdentifier,
  validateIssueMilestones,
} from "../release-milestone.mjs";

test("normalizes tracked FEAT and TD identifiers", () => {
  assert.equal(trackedIssueIdentifier("FEAT-003: Render width presets"), "FEAT-3");
  assert.equal(trackedIssueIdentifier("td-12: Release activation"), "TD-12");
  assert.equal(trackedIssueIdentifier("Test coverage reports"), null);
});

test("extracts squash and merge pull requests from first-parent history", () => {
  const entries = parseFirstParentLog([
    `${"a".repeat(40)}\tFEAT-003: Add output widths (#39)`,
    `${"b".repeat(40)}\tMerge pull request #22 from example/update`,
    `${"c".repeat(40)}\tchore: direct maintenance`,
  ].join("\n"));

  assert.deepEqual(entries.map((entry) => entry.pullRequestNumber), [39, 22, null]);
});

test("selects closing references and manually closed identifier matches", () => {
  const issues = [
    { number: 3, title: "FEAT-003: Render width presets", state: "closed", milestone: null },
    { number: 20, title: "TD-007: Release automation", state: "closed", milestone: null },
    { number: 42, title: "Test Coverage Reports", state: "closed", milestone: null },
    { number: 53, title: "TD-019: Future work", state: "open", milestone: null },
  ];
  const pullRequests = [
    { title: "FEAT-003: Add output widths", closingIssuesReferences: [] },
    { title: "Release workflow", closingIssuesReferences: [{ number: 20 }, { number: 42 }] },
    { title: "TD-019: Partial work", closingIssuesReferences: [{ number: 53 }] },
  ];

  assert.deepEqual(selectReleaseIssues(pullRequests, issues).map((issue) => issue.number), [3, 20]);
});

test("does not remap an older shipped issue from a later same-identifier PR", () => {
  const issues = [{
    number: 46,
    title: "TD-012: Activate releases",
    state: "closed",
    milestone: { title: "v0.4.0" },
  }];
  const pullRequests = [{
    title: "TD-012: Document release maintenance",
    closingIssuesReferences: [],
  }];

  assert.deepEqual(selectReleaseIssues(pullRequests, issues, "v0.5.0"), []);
});

test("refuses to overwrite an issue's existing release milestone", () => {
  assert.throws(
    () => validateIssueMilestones([
      { number: 3, milestone: { title: "v0.3.0" } },
    ], "v0.4.0"),
    /already belongs to milestone v0\.3\.0/,
  );
});

test("renders a reviewable Release PR milestone preview", () => {
  const markdown = releaseMilestoneMarkdown({
    tag: "v0.4.0",
    issues: [{ number: 3, title: "FEAT-003: Render width presets" }],
  });
  assert.match(markdown, /^## Planned v0\.4\.0 issue milestone/m);
  assert.match(markdown, /#3 — FEAT-003: Render width presets/);
});
