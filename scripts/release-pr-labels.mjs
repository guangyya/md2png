#!/usr/bin/env node

import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repositoryPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const commitPattern = /^[0-9a-f]{40}$/;
const stableVersionPattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const bumps = new Set(["patch", "minor", "major"]);

function fail(message) {
  throw new Error(message);
}

function parsePositiveInteger(value, label) {
  if (!/^[1-9][0-9]*$/.test(String(value ?? ""))) {
    fail(`${label} must be a positive integer`);
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    fail(`${label} exceeds the safe integer range`);
  }
  return parsed;
}

function normalizeOptions(options) {
  const repository = options.repository;
  const pullRequest = parsePositiveInteger(options.pullRequest, "pull request number");
  const headSha = options.headSha;
  const headRef = options.headRef;
  const version = options.version;
  const bump = options.bump;
  if (!repositoryPattern.test(repository ?? "")) fail("repository must be OWNER/REPOSITORY");
  if (!commitPattern.test(headSha ?? "")) fail("head SHA must be a lowercase 40-character commit");
  if (headRef !== `codex/release-v${version}`) fail("head ref does not match the release version");
  if (!stableVersionPattern.test(version ?? "")) fail("version must be a stable semantic version");
  if (!bumps.has(bump)) fail("bump must be patch, minor, or major");
  const attempts = options.attempts ?? 5;
  const delayMs = options.delayMs ?? 2_000;
  if (!Number.isSafeInteger(attempts) || attempts < 1 || attempts > 10) {
    fail("attempts must be between 1 and 10");
  }
  if (!Number.isSafeInteger(delayMs) || delayMs < 0 || delayMs > 10_000) {
    fail("delayMs must be between 0 and 10000");
  }
  return { repository, pullRequest, headSha, headRef, version, bump, attempts, delayMs };
}

async function githubJSON(url, token, fetchImpl) {
  const response = await fetchImpl(url, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!response.ok) {
    fail(`GitHub API ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

function validatePullRequestIdentity(pullRequest, expected) {
  if (pullRequest?.number !== expected.pullRequest) fail("live pull request number changed");
  if (pullRequest?.state !== "open") fail("release pull request is not open");
  if (pullRequest?.base?.ref !== "main") fail("release pull request no longer targets main");
  if (pullRequest?.head?.ref !== expected.headRef) fail("live release pull request head ref changed");
  if (pullRequest?.head?.sha !== expected.headSha) fail("live release pull request head SHA changed");
  if (pullRequest?.title !== `Prepare md2png ${expected.version}`) fail("live release pull request title changed");
}

function labelState(pullRequest, bump) {
  if (!Array.isArray(pullRequest.labels)) fail("live pull request labels are unavailable");
  const names = pullRequest.labels.map((label) => label?.name);
  if (names.some((name) => typeof name !== "string" || name.length === 0)) {
    fail("live pull request contains an invalid label");
  }
  const expectedBump = `release:${bump}`;
  const conflicting = names.filter((name) => name.startsWith("release:") && name !== expectedBump);
  if (conflicting.length > 0) {
    fail(`release pull request has a conflicting bump label: ${conflicting.join(", ")}`);
  }
  return {
    names,
    missing: ["release", expectedBump].filter((name) => !names.includes(name)),
  };
}

export async function waitForReleasePullRequestLabels(options, dependencies = {}) {
  const expected = normalizeOptions(options);
  const token = dependencies.token ?? process.env.GITHUB_TOKEN;
  const apiUrl = (dependencies.apiUrl ?? process.env.GITHUB_API_URL ?? "https://api.github.com").replace(/\/$/, "");
  const fetchImpl = dependencies.fetchImpl ?? fetch;
  const sleep = dependencies.sleep ?? ((delayMs) => new Promise((resolve) => setTimeout(resolve, delayMs)));
  if (!token) fail("GITHUB_TOKEN is required");

  let missing = [];
  for (let attempt = 1; attempt <= expected.attempts; attempt += 1) {
    const pullRequest = await githubJSON(
      `${apiUrl}/repos/${expected.repository}/pulls/${expected.pullRequest}`,
      token,
      fetchImpl,
    );
    validatePullRequestIdentity(pullRequest, expected);
    const state = labelState(pullRequest, expected.bump);
    missing = state.missing;
    if (missing.length === 0) {
      return {
        pullRequest: expected.pullRequest,
        headSha: expected.headSha,
        labels: state.names.sort(),
        attempts: attempt,
      };
    }
    if (attempt < expected.attempts) await sleep(expected.delayMs);
  }
  fail(`release pull request is missing required live labels after ${expected.attempts} attempts: ${missing.join(", ")}`);
}

function parseArgs(argv) {
  const [command, ...tokens] = argv;
  if (command !== "verify") fail("command must be verify");
  const options = {};
  for (let index = 0; index < tokens.length; index += 2) {
    const token = tokens[index];
    const value = tokens[index + 1];
    if (!token?.startsWith("--") || value === undefined) fail(`invalid argument: ${token ?? ""}`);
    const key = token.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    if (Object.hasOwn(options, key)) fail(`duplicate option: ${token}`);
    options[key] = value;
  }
  const allowed = ["repository", "pullRequest", "headSha", "headRef", "version", "bump"];
  const unknown = Object.keys(options).filter((key) => !allowed.includes(key));
  if (unknown.length > 0) fail(`unknown option: ${unknown[0]}`);
  return options;
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (invokedPath === fileURLToPath(import.meta.url)) {
  try {
    const result = await waitForReleasePullRequestLabels(parseArgs(process.argv.slice(2)));
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
