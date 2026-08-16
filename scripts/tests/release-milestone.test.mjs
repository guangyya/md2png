import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";

import {
  parseFirstParentLog,
  releaseMilestoneMarkdown,
  releaseMilestoneReviewDigest,
  selectReleaseIssues,
  syncReleaseMilestone,
  trackedIssueIdentifier,
  validateIssueMilestones,
} from "../release-milestone.mjs";

const plan = {
  tag: "v0.5.0",
  version: "0.5.0",
  releaseUrl: "https://github.com/example/md2png/releases/tag/v0.5.0",
  issues: [
    { number: 3, title: "FEAT-003: Render width presets", milestone: null },
    { number: 20, title: "TD-020: Release automation", milestone: null },
  ],
};

async function withMockGitHub(configuration, callback) {
  const calls = [];
  const state = {
    milestone: Object.hasOwn(configuration, "milestone")
      ? configuration.milestone
      : { number: 9, title: plan.tag, state: "open" },
    items: structuredClone(configuration.items ?? []),
    issues: new Map((configuration.issues ?? plan.issues.map((issue) => ({
      ...issue,
      state: "closed",
      milestone: null,
    }))).map((issue) => [issue.number, structuredClone(issue)])),
  };
  state.milestones = structuredClone(configuration.milestones ?? (state.milestone ? [state.milestone] : []));
  const server = http.createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const body = chunks.length > 0 ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : null;
    const url = new URL(request.url, "http://localhost");
    calls.push({ method: request.method, path: url.pathname, query: url.searchParams, body });
    const send = (status, value) => {
      response.writeHead(status, { "Content-Type": "application/json" });
      response.end(JSON.stringify(value));
    };
    if (configuration.fail?.(request.method, url.pathname)) {
      send(500, { message: "injected failure" });
      return;
    }
    if (request.method === "GET" && url.pathname.endsWith("/milestones")) {
      const page = Number(url.searchParams.get("page"));
      send(200, state.milestones.slice((page - 1) * 100, page * 100));
    } else if (request.method === "POST" && url.pathname.endsWith("/milestones")) {
      state.milestone = { number: 9, title: body.title, state: "open" };
      state.milestones.push(state.milestone);
      send(201, state.milestone);
    } else if (request.method === "GET" && url.pathname.endsWith("/issues") && url.searchParams.has("milestone")) {
      send(200, url.searchParams.get("page") === "1" ? state.items : []);
    } else if (request.method === "GET" && /\/issues\/\d+$/.test(url.pathname)) {
      send(200, state.issues.get(Number(url.pathname.split("/").at(-1))));
    } else if (request.method === "PATCH" && /\/issues\/\d+$/.test(url.pathname)) {
      const number = Number(url.pathname.split("/").at(-1));
      const issue = state.issues.get(number);
      issue.milestone = { number: state.milestone.number, title: state.milestone.title };
      if (!state.items.some((item) => item.number === number)) state.items.push(issue);
      send(200, issue);
    } else if (request.method === "PATCH" && /\/milestones\/\d+$/.test(url.pathname)) {
      state.milestone.state = body.state;
      send(200, state.milestone);
    } else {
      send(404, { message: `${request.method} ${url.pathname}` });
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const address = server.address();
    return await callback({
      calls,
      state,
      environment: {
        GITHUB_TOKEN: "test-token",
        GITHUB_REPOSITORY: "example/md2png",
        GITHUB_API_URL: `http://127.0.0.1:${address.port}`,
      },
    });
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

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

test("review digest binds the tag and exact ordered issue preview", () => {
  assert.match(releaseMilestoneReviewDigest(plan), /^[0-9a-f]{64}$/);
  assert.notEqual(
    releaseMilestoneReviewDigest(plan),
    releaseMilestoneReviewDigest({ ...plan, issues: plan.issues.slice(0, 1) }),
  );
});

test("milestone sync resumes partial assignment and closes only after exact verification", async () => {
  const assigned = { ...plan.issues[0], state: "closed", milestone: { number: 9, title: plan.tag } };
  await withMockGitHub({ items: [assigned], issues: [
    assigned,
    { ...plan.issues[1], state: "closed", milestone: null },
  ] }, async ({ calls, environment, state }) => {
    const result = await syncReleaseMilestone(plan, environment);
    assert.equal(result.milestoneState, "closed");
    assert.deepEqual(state.items.map((item) => item.number).sort((a, b) => a - b), [3, 20]);
    const issueWrites = calls.filter((call) => call.method === "PATCH" && /\/issues\//.test(call.path));
    assert.deepEqual(issueWrites.map((call) => call.path), ["/repos/example/md2png/issues/20"]);
    const closeIndex = calls.findIndex((call) => call.method === "PATCH" && /\/milestones\//.test(call.path));
    const finalReadIndex = calls.map((call) => call.path).lastIndexOf("/repos/example/md2png/issues");
    assert.ok(closeIndex > finalReadIndex);
  });
});

test("milestone sync creates a missing milestone idempotently", async () => {
  await withMockGitHub({ milestone: null }, async ({ calls, environment }) => {
    await syncReleaseMilestone(plan, environment);
    assert.equal(calls.filter((call) => call.method === "POST" && call.path.endsWith("/milestones")).length, 1);
  });
});

test("milestone sync paginates lookup and rejects duplicate target milestones", async () => {
  const fillers = Array.from({ length: 100 }, (_, index) => ({
    number: index + 100,
    title: `v0.0.${index}`,
    state: "closed",
  }));
  await withMockGitHub({ milestones: [...fillers, { number: 9, title: plan.tag, state: "open" }] }, async ({ calls, environment }) => {
    await syncReleaseMilestone(plan, environment);
    assert.ok(calls.some((call) => call.path.endsWith("/milestones") && call.query.get("page") === "2"));
  });
  await withMockGitHub({ milestones: [
    { number: 9, title: plan.tag, state: "open" },
    { number: 10, title: plan.tag, state: "closed" },
  ] }, async ({ calls, environment }) => {
    await assert.rejects(syncReleaseMilestone(plan, environment), /multiple milestones are named/);
    assert.equal(calls.some((call) => call.method === "PATCH"), false);
  });
});

test("milestone sync rejects extra, open, and pull request items before mutation", async (context) => {
  const cases = [
    [{ number: 99, title: "Unreviewed", state: "closed", milestone: { title: plan.tag } }, /extra #99/],
    [{ ...plan.issues[0], state: "open", milestone: { title: plan.tag } }, /open items: #3/],
    [{ number: 75, title: "PR", state: "closed", pull_request: {}, milestone: { title: plan.tag } }, /contains pull requests: #75/],
  ];
  for (const [item, expected] of cases) {
    await context.test(expected.source, async () => {
      await withMockGitHub({ items: [item] }, async ({ calls, environment }) => {
        await assert.rejects(syncReleaseMilestone(plan, environment), expected);
        assert.equal(calls.some((call) => call.method === "PATCH"), false);
      });
    });
  }
});

test("milestone sync re-reads each issue and refuses a concurrent other milestone", async () => {
  const moved = { ...plan.issues[0], state: "closed", milestone: { number: 4, title: "v0.4.0" } };
  await withMockGitHub({ issues: [moved, { ...plan.issues[1], state: "closed", milestone: null }] }, async ({ calls, environment }) => {
    await assert.rejects(syncReleaseMilestone(plan, environment), /now belongs to milestone v0\.4\.0/);
    assert.equal(calls.some((call) => call.method === "PATCH"), false);
  });
});

test("milestone API failure leaves the milestone open", async () => {
  await withMockGitHub({
    fail: (method, pathname) => method === "PATCH" && pathname.endsWith("/issues/3"),
  }, async ({ calls, environment, state }) => {
    await assert.rejects(syncReleaseMilestone(plan, environment), /GitHub API 500/);
    assert.equal(state.milestone.state, "open");
    assert.equal(calls.some((call) => call.method === "PATCH" && /\/milestones\//.test(call.path)), false);
  });
});
