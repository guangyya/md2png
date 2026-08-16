import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";

import { resolveReleaseRecoveryHandoff } from "../release-recovery.mjs";

const sourceCommit = "a".repeat(40);
const repository = { id: 42, full_name: "example/md2png" };
const currentRun = {
  id: 200,
  repository,
  workflow_id: 7,
  path: ".github/workflows/release.yml",
  head_branch: "main",
  head_sha: "b".repeat(40),
  status: "in_progress",
  conclusion: null,
  event: "workflow_dispatch",
};
const priorRun = {
  id: 100,
  repository,
  workflow_id: 7,
  path: ".github/workflows/release.yml",
  head_branch: "main",
  head_sha: sourceCommit,
  status: "completed",
  conclusion: "failure",
  event: "push",
};
const artifact = {
  id: 900,
  name: `signed-release-${sourceCommit}`,
  size_in_bytes: 1234,
  expired: false,
  expires_at: "2026-08-17T00:00:00Z",
  workflow_run: {
    id: 100,
    repository_id: 42,
    head_branch: "main",
    head_sha: sourceCommit,
  },
};

async function withMockGitHub(configuration, callback) {
  const calls = [];
  const server = http.createServer((request, response) => {
    const url = new URL(request.url, "http://localhost");
    calls.push(url.pathname + url.search);
    const send = (status, value) => {
      response.writeHead(status, { "Content-Type": "application/json" });
      response.end(JSON.stringify(value));
    };
    if (configuration.failurePath === url.pathname) {
      send(500, { message: "injected failure" });
    } else if (url.pathname.endsWith("/actions/runs/200")) {
      send(200, configuration.currentRun ?? currentRun);
    } else if (url.pathname.endsWith("/actions/runs/100")) {
      send(200, configuration.priorRun ?? priorRun);
    } else if (url.pathname.endsWith("/actions/runs/100/artifacts")) {
      send(200, { artifacts: configuration.artifacts ?? [artifact] });
    } else {
      send(404, { message: `${request.method} ${url.pathname}` });
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const address = server.address();
    return await callback({
      calls,
      options: {
        repository: "example/md2png",
        currentRunId: 200,
        priorRunId: 100,
        sourceCommit,
        workflowCommit: "b".repeat(40),
        artifactName: `signed-release-${sourceCommit}`,
      },
      dependencies: {
        environment: {
          GITHUB_TOKEN: "test-token",
          GITHUB_API_URL: `http://127.0.0.1:${address.port}`,
        },
        now: () => new Date("2026-08-16T00:00:00Z"),
      },
    });
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

test("resolves one unexpired signed handoff bound to the prior release run", async () => {
  await withMockGitHub({}, async ({ options, dependencies }) => {
    assert.deepEqual(await resolveReleaseRecoveryHandoff(options, dependencies), {
      artifactId: 900,
      artifactName: `signed-release-${sourceCommit}`,
      priorRunId: 100,
      priorWorkflowCommit: sourceCommit,
      sourceCommit,
      expiresAt: "2026-08-17T00:00:00Z",
    });
  });
});

test("accepts a prior manual recovery whose trusted workflow commit follows the release source", async () => {
  const priorWorkflowCommit = "c".repeat(40);
  await withMockGitHub({
    priorRun: { ...priorRun, event: "workflow_dispatch", head_sha: priorWorkflowCommit },
    artifacts: [{
      ...artifact,
      workflow_run: { ...artifact.workflow_run, head_sha: priorWorkflowCommit },
    }],
  }, async ({ options, dependencies }) => {
    const result = await resolveReleaseRecoveryHandoff(options, dependencies);
    assert.equal(result.sourceCommit, sourceCommit);
    assert.equal(result.priorWorkflowCommit, priorWorkflowCommit);
  });
});

test("rejects prior run identity drift", async (context) => {
  const cases = [
    [{ repository: { id: 43, full_name: "example/md2png" } }, /same repository identity/],
    [{ workflow_id: 8 }, /current release workflow/],
    [{ path: ".github/workflows/other.yml" }, /current release workflow/],
    [{ head_branch: "topic" }, /must execute from main/],
    [{ event: "schedule" }, /trusted release event/],
    [{ status: "completed", conclusion: "success" }, /completed failed or cancelled/],
  ];
  for (const [change, expected] of cases) {
    await context.test(expected.source, async () => {
      await withMockGitHub({ priorRun: { ...priorRun, ...change } }, async ({ options, dependencies }) => {
        await assert.rejects(resolveReleaseRecoveryHandoff(options, dependencies), expected);
      });
    });
  }
});

test("rejects missing, duplicate, expired, or mismatched handoff artifacts", async (context) => {
  const cases = [
    [[], /exactly one/],
    [[artifact, { ...artifact, id: 901 }], /exactly one/],
    [[{ ...artifact, expired: true }], /has expired/],
    [[{ ...artifact, expires_at: "2026-08-15T00:00:00Z" }], /has expired/],
    [[{ ...artifact, expires_at: "not-a-date" }], /has expired/],
    [[{ ...artifact, size_in_bytes: 0 }], /metadata is invalid/],
    [[{ ...artifact, workflow_run: { ...artifact.workflow_run, head_sha: "d".repeat(40) } }], /identity does not match/],
  ];
  for (const [artifacts, expected] of cases) {
    await context.test(expected.source, async () => {
      await withMockGitHub({ artifacts }, async ({ options, dependencies }) => {
        await assert.rejects(resolveReleaseRecoveryHandoff(options, dependencies), expected);
      });
    });
  }
});

test("rejects API failure and noncanonical input before returning an artifact", async () => {
  await withMockGitHub({ failurePath: "/repos/example/md2png/actions/runs/100" }, async ({ options, dependencies }) => {
    await assert.rejects(resolveReleaseRecoveryHandoff(options, dependencies), /GitHub API 500/);
    await assert.rejects(
      resolveReleaseRecoveryHandoff({ ...options, artifactName: "signed-release-other" }, dependencies),
      /canonical signed release handoff name/,
    );
    await assert.rejects(
      resolveReleaseRecoveryHandoff({ ...options, priorRunId: 201 }, dependencies),
      /must identify an earlier workflow run/,
    );
  });
});
