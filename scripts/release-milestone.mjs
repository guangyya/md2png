#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { realpathSync } from "node:fs";
import process from "node:process";
import { fileURLToPath } from "node:url";

const stableTagPattern = /^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const fullCommitPattern = /^[0-9a-f]{40}$/;
const trackedIssuePattern = /^(FEAT|TD)-0*([1-9][0-9]*)\b/i;

function fail(message) {
  throw new Error(message);
}

function parseStableTag(tag, label = "release tag") {
  const match = stableTagPattern.exec(tag);
  if (!match) {
    fail(`${label} must be v followed by a stable semantic version`);
  }
  return {
    tag,
    version: match.slice(1).join("."),
    parts: match.slice(1).map(Number),
  };
}

function compareVersions(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left.parts[index] !== right.parts[index]) {
      return left.parts[index] - right.parts[index];
    }
  }
  return 0;
}

export function trackedIssueIdentifier(title) {
  const match = trackedIssuePattern.exec(title ?? "");
  return match ? `${match[1].toUpperCase()}-${Number(match[2])}` : null;
}

function pullRequestNumber(subject) {
  const squash = /\(#([1-9][0-9]*)\)\s*$/.exec(subject);
  if (squash) {
    return Number(squash[1]);
  }
  const merge = /^Merge pull request #([1-9][0-9]*)\b/.exec(subject);
  return merge ? Number(merge[1]) : null;
}

export function parseFirstParentLog(output) {
  if (!output.trim()) {
    return [];
  }
  return output.trimEnd().split("\n").map((line) => {
    const separator = line.indexOf("\t");
    if (separator < 0) {
      fail("first-parent Git log contains a malformed entry");
    }
    const sha = line.slice(0, separator);
    const subject = line.slice(separator + 1);
    if (!fullCommitPattern.test(sha)) {
      fail(`first-parent Git log contains an invalid commit: ${sha}`);
    }
    return { sha, subject, pullRequestNumber: pullRequestNumber(subject) };
  });
}

function isTrackedClosedIssue(issue) {
  return issue?.state === "closed" && trackedIssueIdentifier(issue.title) !== null;
}

export function selectReleaseIssues(pullRequests, issues, targetTag = null) {
  const closedIssues = issues.filter(isTrackedClosedIssue);
  const byNumber = new Map(closedIssues.map((issue) => [issue.number, issue]));
  const byIdentifier = new Map();
  for (const issue of closedIssues) {
    const identifier = trackedIssueIdentifier(issue.title);
    const matches = byIdentifier.get(identifier) ?? [];
    matches.push(issue);
    byIdentifier.set(identifier, matches);
  }

  const selected = new Map();
  for (const pullRequest of pullRequests) {
    for (const reference of pullRequest.closingIssuesReferences ?? []) {
      const issue = byNumber.get(reference.number);
      if (issue) {
        selected.set(issue.number, issue);
      }
    }

    const identifier = trackedIssueIdentifier(pullRequest.title);
    if (identifier === null) {
      continue;
    }
    const matches = byIdentifier.get(identifier) ?? [];
    if (matches.length > 1) {
      fail(`multiple closed issues use identifier ${identifier}`);
    }
    if (matches.length === 1) {
      const milestone = matches[0].milestone?.title ?? null;
      if (targetTag === null || milestone === null || milestone === targetTag) {
        selected.set(matches[0].number, matches[0]);
      }
    }
  }
  return [...selected.values()].sort((left, right) => left.number - right.number);
}

export function validateIssueMilestones(issues, tag) {
  for (const issue of issues) {
    const milestone = issue.milestone?.title ?? null;
    if (milestone !== null && milestone !== tag) {
      fail(`issue #${issue.number} already belongs to milestone ${milestone}, not ${tag}`);
    }
  }
}

export function releaseMilestoneMarkdown(plan) {
  const lines = [
    `## Planned ${plan.tag} issue milestone`,
    "",
  ];
  if (plan.issues.length === 0) {
    lines.push("No closed FEAT/TD issue is associated with this release.");
  } else {
    for (const issue of plan.issues) {
      lines.push(`- #${issue.number} — ${issue.title}`);
    }
  }
  return lines.join("\n");
}

export function releaseMilestoneReviewDigest(plan) {
  const reviewedPlan = {
    schemaVersion: 1,
    tag: plan.tag,
    issues: plan.issues.map(({ number, title }) => ({ number, title })),
  };
  return createHash("sha256").update(JSON.stringify(reviewedPlan)).digest("hex");
}

async function mapWithConcurrency(values, limit, mapper) {
  const results = new Array(values.length);
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await mapper(values[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, worker));
  return results;
}

async function githubRequest(url, token, options = {}) {
  const response = await fetch(url, {
    ...options,
    redirect: "follow",
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "md2png-release-milestone",
      ...options.headers,
    },
  });
  if (!response.ok) {
    fail(`GitHub API ${response.status} for ${url}: ${await response.text()}`);
  }
  return response;
}

async function githubJSON(url, token, options = {}) {
  return githubRequest(url, token, options).then((response) => response.json());
}

async function paginatedJSON(apiUrl, token, endpoint) {
  const values = [];
  for (let page = 1; ; page += 1) {
    const url = new URL(`${apiUrl}${endpoint}`);
    url.searchParams.set("per_page", "100");
    url.searchParams.set("page", String(page));
    const pageValues = await githubJSON(url.href, token);
    if (!Array.isArray(pageValues)) {
      fail(`GitHub API endpoint did not return an array: ${endpoint}`);
    }
    values.push(...pageValues);
    if (pageValues.length < 100) {
      return values;
    }
  }
}

async function pullRequestDetails(apiUrl, repository, number, token) {
  const [owner, name] = repository.split("/");
  const query = `
    query ReleasePullRequest($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          number
          title
          merged
          mergeCommit { oid }
          closingIssuesReferences(first: 100) {
            nodes { number }
            pageInfo { hasNextPage }
          }
        }
      }
    }
  `;
  const result = await githubJSON(`${apiUrl}/graphql`, token, {
    method: "POST",
    body: JSON.stringify({ query, variables: { owner, name, number } }),
  });
  if (Array.isArray(result.errors) && result.errors.length > 0) {
    fail(`GitHub GraphQL failed for PR #${number}: ${result.errors.map((error) => error.message).join("; ")}`);
  }
  const pullRequest = result.data?.repository?.pullRequest;
  if (!pullRequest) {
    fail(`cannot resolve PR #${number}`);
  }
  if (pullRequest.closingIssuesReferences.pageInfo.hasNextPage) {
    fail(`PR #${number} closes more than 100 issues`);
  }
  return {
    number: pullRequest.number,
    title: pullRequest.title,
    merged: pullRequest.merged,
    mergeCommit: pullRequest.mergeCommit?.oid ?? null,
    closingIssuesReferences: pullRequest.closingIssuesReferences.nodes,
  };
}

function git(repoRoot, args, options = {}) {
  return execFileSync("git", ["-C", repoRoot, ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  }).trim();
}

function releaseCommitEntries(repoRoot, previousTag, sourceCommit) {
  const previousCommit = git(repoRoot, ["rev-parse", `${previousTag}^{}`]);
  if (!fullCommitPattern.test(previousCommit)) {
    fail(`${previousTag} does not resolve to a full Git commit`);
  }
  try {
    git(repoRoot, ["merge-base", "--is-ancestor", previousCommit, sourceCommit]);
  } catch {
    fail(`${previousTag} is not an ancestor of release commit ${sourceCommit}`);
  }
  const output = git(repoRoot, [
    "log",
    "--first-parent",
    "--format=%H%x09%s",
    `${previousCommit}..${sourceCommit}`,
  ]);
  return parseFirstParentLog(output);
}

function normalizedEnvironment(environment) {
  const token = environment.GITHUB_TOKEN;
  const repository = environment.GITHUB_REPOSITORY ?? environment.GH_REPO;
  const apiUrl = (environment.GITHUB_API_URL ?? "https://api.github.com").replace(/\/$/, "");
  const serverUrl = (environment.GITHUB_SERVER_URL ?? "https://github.com").replace(/\/$/, "");
  const repoRoot = environment.REPO_ROOT ?? process.cwd();
  if (!token) {
    fail("GITHUB_TOKEN is required");
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? "")) {
    fail("GITHUB_REPOSITORY or GH_REPO must be OWNER/REPOSITORY");
  }
  return { token, repository, apiUrl, serverUrl, repoRoot };
}

export async function planReleaseMilestone({ tag, sourceCommit }, environment = process.env) {
  const target = parseStableTag(tag);
  if (!fullCommitPattern.test(sourceCommit ?? "")) {
    fail("source commit must be a full lowercase commit SHA");
  }
  const { token, repository, apiUrl, serverUrl, repoRoot } = normalizedEnvironment(environment);
  const latestRelease = await githubJSON(`${apiUrl}/repos/${repository}/releases/latest`, token);
  const previous = parseStableTag(latestRelease.tag_name, "latest stable release tag");
  if (compareVersions(previous, target) >= 0) {
    fail(`${tag} must be newer than latest stable release ${previous.tag}`);
  }

  const entries = releaseCommitEntries(repoRoot, previous.tag, sourceCommit);
  const pullRequestEntries = entries.filter((entry) => entry.pullRequestNumber !== null);
  const pullRequests = await mapWithConcurrency(pullRequestEntries, 4, async (entry) => {
    const pullRequest = await pullRequestDetails(
      apiUrl,
      repository,
      entry.pullRequestNumber,
      token,
    );
    if (!pullRequest.merged || pullRequest.mergeCommit !== entry.sha) {
      fail(`PR #${pullRequest.number} does not match release-history commit ${entry.sha}`);
    }
    return pullRequest;
  });
  const issueResponses = await paginatedJSON(apiUrl, token, `/repos/${repository}/issues?state=closed`);
  const issues = issueResponses.filter((issue) => !issue.pull_request);
  const selectedIssues = selectReleaseIssues(pullRequests, issues, tag);
  validateIssueMilestones(selectedIssues, tag);
  const plan = {
    tag,
    version: target.version,
    previousTag: previous.tag,
    sourceCommit,
    releaseUrl: `${serverUrl}/${repository}/releases/tag/${tag}`,
    pullRequests: pullRequests.map((pullRequest) => ({
      number: pullRequest.number,
      title: pullRequest.title,
    })),
    issues: selectedIssues.map((issue) => ({
      number: issue.number,
      title: issue.title,
      milestone: issue.milestone?.title ?? null,
    })),
  };
  return { ...plan, reviewDigest: releaseMilestoneReviewDigest(plan) };
}

function validateMilestoneItems(items, plan, { allowMissing }) {
  const pullRequests = items.filter((item) => item.pull_request);
  if (pullRequests.length > 0) {
    fail(`${plan.tag} milestone contains pull requests: ${pullRequests.map((item) => `#${item.number}`).join(", ")}`);
  }
  const openItems = items.filter((item) => item.state !== "closed");
  if (openItems.length > 0) {
    fail(`${plan.tag} milestone still contains open items: ${openItems.map((item) => `#${item.number}`).join(", ")}`);
  }
  const expected = new Set(plan.issues.map((issue) => issue.number));
  if (expected.size !== plan.issues.length) {
    fail("release milestone plan contains duplicate issue numbers");
  }
  const actual = new Set(items.map((item) => item.number));
  const extra = [...actual].filter((number) => !expected.has(number)).sort((left, right) => left - right);
  const missing = [...expected].filter((number) => !actual.has(number)).sort((left, right) => left - right);
  if (extra.length > 0 || (!allowMissing && missing.length > 0)) {
    const details = [];
    if (missing.length > 0) details.push(`missing ${missing.map((number) => `#${number}`).join(", ")}`);
    if (extra.length > 0) details.push(`extra ${extra.map((number) => `#${number}`).join(", ")}`);
    fail(`${plan.tag} milestone membership differs from the reviewed plan: ${details.join("; ")}`);
  }
  return { missing };
}

export async function syncReleaseMilestone(plan, environment = process.env, retryOptions = {}) {
  const membershipAttempts = retryOptions.membershipAttempts ?? 5;
  const membershipDelayMs = retryOptions.membershipDelayMs ?? 2_000;
  const sleep = retryOptions.sleep ?? ((delayMs) => new Promise((resolve) => setTimeout(resolve, delayMs)));
  if (!Number.isSafeInteger(membershipAttempts) || membershipAttempts < 1 || membershipAttempts > 10) {
    fail("milestone membership attempts must be between 1 and 10");
  }
  if (!Number.isSafeInteger(membershipDelayMs) || membershipDelayMs < 0 || membershipDelayMs > 10_000) {
    fail("milestone membership delay must be between 0 and 10000 milliseconds");
  }
  const { token, repository, apiUrl, serverUrl } = normalizedEnvironment(environment);
  const milestones = await paginatedJSON(apiUrl, token, `/repos/${repository}/milestones?state=all`);
  const matches = milestones.filter((milestone) => milestone.title === plan.tag);
  if (matches.length > 1) {
    fail(`multiple milestones are named ${plan.tag}`);
  }
  let milestone = matches[0] ?? null;
  if (milestone === null) {
    milestone = await githubJSON(`${apiUrl}/repos/${repository}/milestones`, token, {
      method: "POST",
      body: JSON.stringify({
        title: plan.tag,
        state: "open",
        description: `Issues shipped in [md2png ${plan.version}](${plan.releaseUrl}).`,
      }),
    });
  }

  const milestoneItems = await paginatedJSON(
    apiUrl,
    token,
    `/repos/${repository}/issues?state=all&milestone=${milestone.number}`,
  );
  validateMilestoneItems(milestoneItems, plan, { allowMissing: true });

  for (const issue of plan.issues) {
    const current = await githubJSON(`${apiUrl}/repos/${repository}/issues/${issue.number}`, token);
    if (current.pull_request) {
      fail(`planned issue #${issue.number} is a pull request`);
    }
    if (current.state !== "closed") {
      fail(`planned issue #${issue.number} is no longer closed`);
    }
    if (current.title !== issue.title) {
      fail(`planned issue #${issue.number} title changed after review`);
    }
    const currentMilestone = current.milestone?.title ?? null;
    if (currentMilestone !== null && currentMilestone !== plan.tag) {
      fail(`issue #${issue.number} now belongs to milestone ${currentMilestone}, not ${plan.tag}`);
    }
    if (currentMilestone === plan.tag) {
      continue;
    }
    const updated = await githubJSON(`${apiUrl}/repos/${repository}/issues/${issue.number}`, token, {
      method: "PATCH",
      body: JSON.stringify({ milestone: milestone.number }),
    });
    if (updated.milestone?.title !== plan.tag) {
      fail(`issue #${issue.number} was not assigned to milestone ${plan.tag}`);
    }
  }

  let missing = [];
  for (let attempt = 1; attempt <= membershipAttempts; attempt += 1) {
    const verifiedItems = await paginatedJSON(
      apiUrl,
      token,
      `/repos/${repository}/issues?state=all&milestone=${milestone.number}`,
    );
    ({ missing } = validateMilestoneItems(verifiedItems, plan, { allowMissing: true }));
    if (missing.length === 0) break;
    if (attempt < membershipAttempts) await sleep(membershipDelayMs);
  }
  if (missing.length > 0) {
    fail(`${plan.tag} milestone membership differs from the reviewed plan after ${membershipAttempts} attempts: missing ${missing.map((number) => `#${number}`).join(", ")}`);
  }
  if (milestone.state !== "closed") {
    milestone = await githubJSON(`${apiUrl}/repos/${repository}/milestones/${milestone.number}`, token, {
      method: "PATCH",
      body: JSON.stringify({ state: "closed" }),
    });
  }
  return {
    ...plan,
    milestoneNumber: milestone.number,
    milestoneUrl: `${serverUrl}/${repository}/milestone/${milestone.number}`,
    milestoneState: milestone.state,
  };
}

function parseOptions(argv) {
  const [command, ...rest] = argv;
  if (!["plan", "sync"].includes(command)) {
    fail("command must be plan or sync");
  }
  const options = {};
  for (let index = 0; index < rest.length; index += 2) {
    const name = rest[index];
    const value = rest[index + 1];
    if (!name?.startsWith("--") || value === undefined) {
      fail("options must use --name value pairs");
    }
    const key = name.slice(2);
    if (!["tag", "source-commit", "expected-review-digest"].includes(key)) {
      fail(`unknown option: ${name}`);
    }
    if (Object.hasOwn(options, key)) {
      fail(`duplicate option: ${name}`);
    }
    options[key] = value;
  }
  if (!options.tag || !options["source-commit"]) {
    fail("--tag and --source-commit are required");
  }
  const expectedReviewDigest = options["expected-review-digest"] ?? null;
  if (expectedReviewDigest !== null && !/^[0-9a-f]{64}$/.test(expectedReviewDigest)) {
    fail("--expected-review-digest must be a lowercase SHA-256 digest");
  }
  return { command, tag: options.tag, sourceCommit: options["source-commit"], expectedReviewDigest };
}

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const plan = await planReleaseMilestone(options);
  if (options.expectedReviewDigest !== null && plan.reviewDigest !== options.expectedReviewDigest) {
    fail(`release milestone plan digest ${plan.reviewDigest} does not match reviewed digest ${options.expectedReviewDigest}`);
  }
  const result = options.command === "sync" ? await syncReleaseMilestone(plan) : plan;
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

const modulePath = realpathSync(fileURLToPath(import.meta.url));
const invokedPath = process.argv[1] ? realpathSync(process.argv[1]) : null;
if (invokedPath !== null && modulePath === invokedPath) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
