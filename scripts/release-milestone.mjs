#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import process from "node:process";
import { pathToFileURL } from "node:url";

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
  const pullRequests = await Promise.all(pullRequestEntries.map(async (entry) => {
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
  }));
  const issueResponses = await paginatedJSON(apiUrl, token, `/repos/${repository}/issues?state=closed`);
  const issues = issueResponses.filter((issue) => !issue.pull_request);
  const selectedIssues = selectReleaseIssues(pullRequests, issues, tag);
  validateIssueMilestones(selectedIssues, tag);
  return {
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
}

async function syncReleaseMilestone(plan, environment = process.env) {
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
  const openItems = milestoneItems.filter((item) => item.state !== "closed");
  if (openItems.length > 0) {
    fail(`${plan.tag} milestone still contains open items: ${openItems.map((item) => `#${item.number}`).join(", ")}`);
  }

  for (const issue of plan.issues) {
    if (issue.milestone === plan.tag) {
      continue;
    }
    await githubJSON(`${apiUrl}/repos/${repository}/issues/${issue.number}`, token, {
      method: "PATCH",
      body: JSON.stringify({ milestone: milestone.number }),
    });
  }

  const verifiedItems = await paginatedJSON(
    apiUrl,
    token,
    `/repos/${repository}/issues?state=all&milestone=${milestone.number}`,
  );
  const verifiedIssueNumbers = new Set(
    verifiedItems.filter((item) => !item.pull_request).map((item) => item.number),
  );
  for (const issue of plan.issues) {
    if (!verifiedIssueNumbers.has(issue.number)) {
      fail(`issue #${issue.number} was not assigned to milestone ${plan.tag}`);
    }
  }
  if (verifiedItems.some((item) => item.state !== "closed")) {
    fail(`${plan.tag} milestone cannot close while it contains open items`);
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
    if (!["tag", "source-commit"].includes(key)) {
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
  return { command, tag: options.tag, sourceCommit: options["source-commit"] };
}

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const plan = await planReleaseMilestone(options);
  const result = options.command === "sync" ? await syncReleaseMilestone(plan) : plan;
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
