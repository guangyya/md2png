#!/usr/bin/env node

import { pathToFileURL } from "node:url";

import { validateCoverageReport } from "./coverage-report.mjs";

export const HISTORY_START_MARKER = "<!-- coverage-history:start -->";
export const HISTORY_END_MARKER = "<!-- coverage-history:end -->";
export const HISTORY_ISSUE_TITLE = "Test coverage history";

function fail(message) {
  throw new Error(message);
}

function parseStableTag(tag) {
  const match = /^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.exec(tag);
  if (!match) {
    return null;
  }
  return {
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

function markdownEscape(value) {
  return String(value).replaceAll("|", "\\|");
}

function signedDelta(value) {
  if (value === null) {
    return "—";
  }
  return `${value >= 0 ? "+" : ""}${value.toFixed(2)} pp`;
}

export function buildHistorySection(snapshots, warnings, options = {}) {
  const serverUrl = options.serverUrl ?? "https://github.com";
  const repository = options.repository ?? "OWNER/REPOSITORY";
  const normalizedSnapshots = snapshots.map((snapshot) => {
    const parsedTag = parseStableTag(snapshot.tag);
    if (parsedTag === null) {
      fail(`history snapshot has invalid stable tag: ${snapshot.tag}`);
    }
    validateCoverageReport(snapshot.report, { appVersion: parsedTag.version });
    if (typeof snapshot.releaseDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(snapshot.releaseDate)) {
      fail(`history snapshot ${snapshot.tag} has invalid releaseDate`);
    }
    if (typeof snapshot.tagCommit !== "string" || !/^[0-9a-f]{40}$/.test(snapshot.tagCommit)) {
      fail(`history snapshot ${snapshot.tag} has invalid tagCommit`);
    }
    if (snapshot.report.commit !== snapshot.tagCommit) {
      fail(`history snapshot ${snapshot.tag} report commit does not match its release tag`);
    }
    return { ...snapshot, ...parsedTag };
  }).sort(compareVersions);

  const lines = [
    HISTORY_START_MARKER,
    "## Coverage trend",
    "",
    "Versioned GitHub Release JSON assets are the source of truth. This section is regenerated after a release.",
    "",
  ];

  if (normalizedSnapshots.length > 0) {
    const labels = normalizedSnapshots.map((snapshot) => JSON.stringify(snapshot.tag)).join(", ");
    const percentages = normalizedSnapshots
      .map((snapshot) => snapshot.report.totals.percentage.toFixed(2))
      .join(", ");
    lines.push(
      "```mermaid",
      "xychart-beta",
      "    title \"Source-line coverage by release\"",
      `    x-axis [${labels}]`,
      "    y-axis \"Coverage (%)\" 0 --> 100",
      `    line [${percentages}]`,
      "```",
      "",
      "| Version | Release date | Covered / total lines | Coverage | Delta | Commit |",
      "| --- | --- | ---: | ---: | ---: | --- |",
    );

    let previousPercentage = null;
    for (const snapshot of normalizedSnapshots) {
      const percentage = snapshot.report.totals.percentage;
      const delta = previousPercentage === null
        ? null
        : Math.round((percentage - previousPercentage) * 100) / 100;
      const commit = snapshot.report.commit;
      lines.push(
        `| [${markdownEscape(snapshot.tag)}](${snapshot.releaseUrl}) | ${snapshot.releaseDate} | ${snapshot.report.totals.coveredLines.toLocaleString("en-US")} / ${snapshot.report.totals.coverableLines.toLocaleString("en-US")} | ${percentage.toFixed(2)}% | ${signedDelta(delta)} | [\`${commit.slice(0, 7)}\`](${serverUrl}/${repository}/commit/${commit}) |`,
      );
      previousPercentage = percentage;
    }
    lines.push("");
  } else {
    lines.push("No valid coverage snapshots are available yet.", "");
  }

  if (warnings.length > 0) {
    lines.push("### Snapshot warnings", "");
    for (const warning of [...warnings].sort()) {
      lines.push(`- ${markdownEscape(warning)}`);
    }
    lines.push("");
  }

  lines.push(HISTORY_END_MARKER);
  return lines.join("\n");
}

export function replaceGeneratedSection(issueBody, generatedSection) {
  if (typeof issueBody !== "string") {
    fail("coverage history issue body must be a string");
  }
  const start = issueBody.indexOf(HISTORY_START_MARKER);
  const end = issueBody.indexOf(HISTORY_END_MARKER);
  if (start < 0 || end < 0 || end < start) {
    fail("coverage history issue is missing valid generated-section markers");
  }
  if (issueBody.indexOf(HISTORY_START_MARKER, start + 1) >= 0
      || issueBody.indexOf(HISTORY_END_MARKER, end + 1) >= 0) {
    fail("coverage history issue contains duplicate generated-section markers");
  }
  const suffixStart = end + HISTORY_END_MARKER.length;
  return `${issueBody.slice(0, start)}${generatedSection}${issueBody.slice(suffixStart)}`;
}

async function githubRequest(url, token, options = {}) {
  const response = await fetch(url, {
    ...options,
    redirect: "follow",
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "md2png-coverage-history",
      ...options.headers,
    },
  });
  if (!response.ok) {
    fail(`GitHub API ${response.status} for ${url}: ${await response.text()}`);
  }
  return response;
}

async function paginatedJSON(apiUrl, token, endpoint) {
  const values = [];
  for (let page = 1; ; page += 1) {
    const requestUrl = new URL(`${apiUrl}${endpoint}`);
    requestUrl.searchParams.set("per_page", "100");
    requestUrl.searchParams.set("page", String(page));
    const response = await githubRequest(requestUrl.href, token);
    const pageValues = await response.json();
    if (!Array.isArray(pageValues)) {
      fail(`GitHub API endpoint did not return an array: ${endpoint}`);
    }
    values.push(...pageValues);
    if (pageValues.length < 100) {
      return values;
    }
  }
}

async function downloadCoverageReport(asset, token) {
  const response = await githubRequest(asset.url, token, {
    headers: { Accept: "application/octet-stream" },
  });
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch (error) {
    fail(`asset ${asset.name} is not valid JSON: ${error.message}`);
  }
}

async function resolveTagCommit(apiUrl, repository, tag, token) {
  const refResponse = await githubRequest(
    `${apiUrl}/repos/${repository}/git/ref/tags/${encodeURIComponent(tag)}`,
    token,
  );
  let object = (await refResponse.json()).object;
  for (let depth = 0; depth < 5; depth += 1) {
    if (object?.type === "commit" && /^[0-9a-f]{40}$/.test(object.sha ?? "")) {
      return object.sha;
    }
    if (object?.type !== "tag" || !/^[0-9a-f]{40}$/.test(object.sha ?? "")) {
      fail(`release tag ${tag} does not resolve to a Git commit`);
    }
    const tagResponse = await githubRequest(
      `${apiUrl}/repos/${repository}/git/tags/${object.sha}`,
      token,
    );
    object = (await tagResponse.json()).object;
  }
  fail(`release tag ${tag} has too many nested tag objects`);
}

export async function updateCoverageHistory(environment = process.env) {
  const token = environment.GITHUB_TOKEN;
  const repository = environment.GITHUB_REPOSITORY;
  const apiUrl = (environment.GITHUB_API_URL ?? "https://api.github.com").replace(/\/$/, "");
  const serverUrl = (environment.GITHUB_SERVER_URL ?? "https://github.com").replace(/\/$/, "");
  if (!token) {
    fail("GITHUB_TOKEN is required");
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? "")) {
    fail("GITHUB_REPOSITORY must be OWNER/REPOSITORY");
  }

  const releases = await paginatedJSON(apiUrl, token, `/repos/${repository}/releases`);
  const snapshots = [];
  const warnings = [];
  for (const release of releases) {
    const parsedTag = parseStableTag(release.tag_name);
    if (release.draft || release.prerelease || parsedTag === null) {
      continue;
    }
    const expectedAssetName = `md2png-${parsedTag.version}-coverage.json`;
    const matchingAssets = Array.isArray(release.assets)
      ? release.assets.filter((asset) => asset.name === expectedAssetName)
      : [];
    if (matchingAssets.length !== 1) {
      warnings.push(`\`${release.tag_name}\`: expected exactly one \`${expectedAssetName}\` asset, found ${matchingAssets.length}.`);
      continue;
    }
    try {
      const report = await downloadCoverageReport(matchingAssets[0], token);
      const tagCommit = await resolveTagCommit(apiUrl, repository, release.tag_name, token);
      validateCoverageReport(report, { appVersion: parsedTag.version, commit: tagCommit });
      snapshots.push({
        tag: release.tag_name,
        tagCommit,
        releaseDate: String(release.published_at ?? release.created_at).slice(0, 10),
        releaseUrl: release.html_url,
        report,
      });
    } catch (error) {
      warnings.push(`\`${release.tag_name}\`: ${error.message}`);
    }
  }

  const issues = await paginatedJSON(apiUrl, token, `/repos/${repository}/issues?state=open`);
  const historyIssues = issues.filter((issue) => !issue.pull_request && issue.title === HISTORY_ISSUE_TITLE);
  if (historyIssues.length !== 1) {
    fail(`expected exactly one open issue named ${HISTORY_ISSUE_TITLE}, found ${historyIssues.length}`);
  }
  const issue = historyIssues[0];
  const generatedSection = buildHistorySection(snapshots, warnings, { repository, serverUrl });
  const body = replaceGeneratedSection(issue.body ?? "", generatedSection);
  if (body === issue.body) {
    process.stdout.write(`Coverage history issue #${issue.number} is already current.\n`);
    return;
  }
  await githubRequest(`${apiUrl}/repos/${repository}/issues/${issue.number}`, token, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ body }),
  });
  process.stdout.write(`Updated coverage history issue #${issue.number}.\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await updateCoverageHistory();
  } catch (error) {
    process.stderr.write(`coverage-history: ${error.message}\n`);
    process.exitCode = 1;
  }
}
