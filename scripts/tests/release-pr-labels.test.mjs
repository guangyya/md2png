import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";

import { waitForReleasePullRequestLabels } from "../release-pr-labels.mjs";

const headSha = "a".repeat(40);
const options = {
  repository: "example/md2png",
  pullRequest: 80,
  headSha,
  headRef: "codex/release-v0.5.0",
  version: "0.5.0",
  bump: "minor",
  attempts: 3,
  delayMs: 0,
};

function pullRequest(labels, overrides = {}) {
  return {
    number: 80,
    state: "open",
    title: "Prepare md2png 0.5.0",
    base: { ref: "main" },
    head: { ref: "codex/release-v0.5.0", sha: headSha },
    labels: labels.map((name) => ({ name })),
    ...overrides,
  };
}

async function withPullRequestResponses(responses, callback) {
  let requestCount = 0;
  const server = http.createServer((request, response) => {
    requestCount += 1;
    const value = responses[Math.min(requestCount - 1, responses.length - 1)];
    const status = value.status ?? 200;
    response.writeHead(status, { "Content-Type": "application/json" });
    response.end(JSON.stringify(value.body ?? value));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const address = server.address();
    return await callback({
      requestCount: () => requestCount,
      dependencies: {
        token: "test-token",
        apiUrl: `http://127.0.0.1:${address.port}`,
        sleep: async () => {},
      },
    });
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

test("accepts exact live release labels without retrying", async () => {
  await withPullRequestResponses([
    pullRequest(["release", "release:minor", "documentation"]),
  ], async ({ dependencies, requestCount }) => {
    const result = await waitForReleasePullRequestLabels(options, dependencies);
    assert.equal(result.attempts, 1);
    assert.deepEqual(result.labels, ["documentation", "release", "release:minor"]);
    assert.equal(requestCount(), 1);
  });
});

test("retries an empty opened-event state until live labels are visible", async () => {
  await withPullRequestResponses([
    pullRequest([]),
    pullRequest(["release"]),
    pullRequest(["release", "release:minor"]),
  ], async ({ dependencies, requestCount }) => {
    const result = await waitForReleasePullRequestLabels(options, dependencies);
    assert.equal(result.attempts, 3);
    assert.equal(requestCount(), 3);
  });
});

test("fails closed when required labels never appear", async () => {
  await withPullRequestResponses([
    pullRequest([]),
  ], async ({ dependencies, requestCount }) => {
    await assert.rejects(
      waitForReleasePullRequestLabels(options, dependencies),
      /missing required live labels after 3 attempts: release, release:minor/,
    );
    assert.equal(requestCount(), 3);
  });
});

test("rejects a conflicting bump label without retrying", async () => {
  await withPullRequestResponses([
    pullRequest(["release", "release:patch"]),
  ], async ({ dependencies, requestCount }) => {
    await assert.rejects(
      waitForReleasePullRequestLabels(options, dependencies),
      /conflicting bump label: release:patch/,
    );
    assert.equal(requestCount(), 1);
  });
});

test("rejects live pull request identity drift and API failure", async (context) => {
  await context.test("head SHA drift", async () => {
    await withPullRequestResponses([
      pullRequest(["release", "release:minor"], { head: { ref: options.headRef, sha: "b".repeat(40) } }),
    ], async ({ dependencies }) => {
      await assert.rejects(waitForReleasePullRequestLabels(options, dependencies), /head SHA changed/);
    });
  });
  await context.test("API failure", async () => {
    await withPullRequestResponses([
      { status: 500, body: { message: "injected failure" } },
    ], async ({ dependencies, requestCount }) => {
      await assert.rejects(waitForReleasePullRequestLabels(options, dependencies), /GitHub API 500/);
      assert.equal(requestCount(), 1);
    });
  });
});
