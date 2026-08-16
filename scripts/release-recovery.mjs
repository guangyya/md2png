#!/usr/bin/env node

import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

function fail(message) {
  throw new Error(message);
}

function exactPositiveInteger(value, label) {
  const normalized = String(value ?? "");
  if (!/^[1-9][0-9]*$/.test(normalized)) fail(`${label} must be a positive integer`);
  const number = Number(normalized);
  if (!Number.isSafeInteger(number)) fail(`${label} is outside the supported range`);
  return number;
}

function exactCommit(value, label) {
  const normalized = String(value ?? "");
  if (!/^[0-9a-f]{40}$/.test(normalized)) fail(`${label} must be an exact 40-character commit SHA`);
  return normalized;
}

function exactRepository(value) {
  const normalized = String(value ?? "");
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(normalized)) {
    fail("repository must use the owner/name form");
  }
  return normalized;
}

async function githubJSON(apiUrl, token, pathname, fetchImplementation) {
  const response = await fetchImplementation(`${apiUrl}${pathname}`, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!response.ok) {
    const body = await response.text();
    fail(`GitHub API ${response.status} for ${pathname}: ${body}`);
  }
  return response.json();
}

async function allRunArtifacts(apiUrl, token, repository, runId, fetchImplementation) {
  const artifacts = [];
  for (let page = 1; ; page += 1) {
    const response = await githubJSON(
      apiUrl,
      token,
      `/repos/${repository}/actions/runs/${runId}/artifacts?per_page=100&page=${page}`,
      fetchImplementation,
    );
    if (!Array.isArray(response.artifacts)) fail("GitHub artifact response is malformed");
    artifacts.push(...response.artifacts);
    if (response.artifacts.length < 100) break;
  }
  return artifacts;
}

export async function resolveReleaseRecoveryHandoff(options, dependencies = {}) {
  const repository = exactRepository(options.repository);
  const currentRunId = exactPositiveInteger(options.currentRunId, "current run ID");
  const priorRunId = exactPositiveInteger(options.priorRunId, "prior run ID");
  const sourceCommit = exactCommit(options.sourceCommit, "source commit");
  const workflowCommit = exactCommit(options.workflowCommit, "workflow commit");
  const artifactName = String(options.artifactName ?? "");
  if (artifactName !== `signed-release-${sourceCommit}`) {
    fail("artifact name must be the canonical signed release handoff name");
  }
  if (priorRunId >= currentRunId) fail("prior run ID must identify an earlier workflow run");

  const environment = dependencies.environment ?? process.env;
  const token = environment.GITHUB_TOKEN;
  const apiUrl = (environment.GITHUB_API_URL ?? "https://api.github.com").replace(/\/$/, "");
  if (!token) fail("GITHUB_TOKEN is required");
  const fetchImplementation = dependencies.fetchImplementation ?? fetch;
  const now = dependencies.now ?? (() => new Date());

  const [currentRun, priorRun] = await Promise.all([
    githubJSON(apiUrl, token, `/repos/${repository}/actions/runs/${currentRunId}`, fetchImplementation),
    githubJSON(apiUrl, token, `/repos/${repository}/actions/runs/${priorRunId}`, fetchImplementation),
  ]);
  if (currentRun.id !== currentRunId || priorRun.id !== priorRunId) {
    fail("GitHub returned an unexpected workflow run identity");
  }
  if (currentRun.repository?.full_name !== repository || priorRun.repository?.full_name !== repository) {
    fail("recovery runs must belong to the requested repository");
  }
  if (!Number.isSafeInteger(currentRun.repository?.id)
    || currentRun.repository.id !== priorRun.repository?.id) {
    fail("recovery runs do not share the same repository identity");
  }
  if (!Number.isSafeInteger(currentRun.workflow_id)
    || currentRun.workflow_id !== priorRun.workflow_id
    || currentRun.path !== priorRun.path) {
    fail("prior run does not belong to the current release workflow");
  }
  if (currentRun.path !== ".github/workflows/release.yml") {
    fail("current run is not using the trusted release workflow");
  }
  if (currentRun.head_branch !== "main" || priorRun.head_branch !== "main") {
    fail("recovery runs must execute from main");
  }
  if (currentRun.head_sha !== workflowCommit || !/^[0-9a-f]{40}$/.test(priorRun.head_sha ?? "")) {
    fail("recovery workflow commit identity is invalid");
  }
  if (!["push", "workflow_dispatch"].includes(priorRun.event)) {
    fail("prior run was not triggered by a trusted release event");
  }
  if (priorRun.status !== "completed"
    || !["failure", "cancelled", "timed_out"].includes(priorRun.conclusion)) {
    fail("prior run must be a completed failed or cancelled release attempt");
  }

  const artifacts = await allRunArtifacts(apiUrl, token, repository, priorRunId, fetchImplementation);
  const matches = artifacts.filter((artifact) => artifact.name === artifactName);
  if (matches.length !== 1) {
    fail(`prior run must contain exactly one ${artifactName} artifact; found ${matches.length}`);
  }
  const artifact = matches[0];
  if (!Number.isSafeInteger(artifact.id) || artifact.id < 1
    || !Number.isSafeInteger(artifact.size_in_bytes) || artifact.size_in_bytes < 1) {
    fail("signed release handoff artifact metadata is invalid");
  }
  const expiresAt = new Date(artifact.expires_at ?? "");
  if (artifact.expired !== false || !Number.isFinite(expiresAt.valueOf()) || expiresAt <= now()) {
    fail("signed release handoff artifact has expired");
  }
  if (artifact.workflow_run?.id !== priorRunId
    || artifact.workflow_run?.repository_id !== priorRun.repository.id
    || artifact.workflow_run?.head_branch !== "main"
    || artifact.workflow_run?.head_sha !== priorRun.head_sha) {
    fail("signed release handoff artifact identity does not match the prior run");
  }

  return {
    artifactId: artifact.id,
    artifactName,
    priorRunId,
    priorWorkflowCommit: priorRun.head_sha,
    sourceCommit,
    expiresAt: artifact.expires_at,
  };
}

function parseArguments(arguments_) {
  if (arguments_[0] !== "resolve") fail("usage: release-recovery.mjs resolve [options]");
  const values = {};
  for (let index = 1; index < arguments_.length; index += 2) {
    const name = arguments_[index];
    const value = arguments_[index + 1];
    if (!name?.startsWith("--") || value === undefined) fail(`invalid argument: ${name ?? ""}`);
    if (Object.hasOwn(values, name)) fail(`duplicate argument: ${name}`);
    values[name] = value;
  }
  const expected = ["--repository", "--current-run", "--prior-run", "--source-commit", "--workflow-commit", "--artifact-name"];
  for (const name of expected) {
    if (!Object.hasOwn(values, name)) fail(`missing required argument: ${name}`);
  }
  if (Object.keys(values).some((name) => !expected.includes(name))) fail("unknown argument");
  return {
    repository: values["--repository"],
    currentRunId: values["--current-run"],
    priorRunId: values["--prior-run"],
    sourceCommit: values["--source-commit"],
    workflowCommit: values["--workflow-commit"],
    artifactName: values["--artifact-name"],
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = await resolveReleaseRecoveryHandoff(parseArguments(process.argv.slice(2)));
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
