import { createHash } from "node:crypto";
import { realpathSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const checkoutIDPattern = /^[0-9a-f]{12}$/;

export function checkoutIdentity(repoRoot) {
  const canonicalRoot = realpathSync.native(path.resolve(repoRoot));
  return createHash("sha256").update(canonicalRoot).digest("hex").slice(0, 12);
}

export function debugBundleIdentifier(baseBundleIdentifier, checkoutID) {
  if (!/^[A-Za-z0-9.-]+$/.test(baseBundleIdentifier)) {
    throw new Error("base bundle identifier contains unsupported characters");
  }
  if (!checkoutIDPattern.test(checkoutID)) {
    throw new Error("checkout identity must contain 12 lowercase hexadecimal characters");
  }
  return `${baseBundleIdentifier}.debug-${checkoutID}`;
}

export function parseProcessTable(output) {
  return output
    .split("\n")
    .map((line) => line.match(/^\s*(\d+)\s+(.+?)\s*$/))
    .filter(Boolean)
    .map((match) => ({ pid: Number(match[1]), command: match[2] }));
}

export function matchingProcessIDs(processes, executablePath, currentPID = process.pid) {
  const canonicalExecutable = path.resolve(executablePath);
  return processes
    .filter(({ pid, command }) => pid !== currentPID && command === canonicalExecutable)
    .map(({ pid }) => pid);
}

export function shouldRetryOpenFailure(detail) {
  return /(?:error|code)\s+-(?:600|609)\b/.test(detail);
}

export function parseOptions(args, allowedOptions) {
  const allowed = new Set(allowedOptions);
  const options = {};
  for (let index = 0; index < args.length; index += 2) {
    const option = args[index];
    const value = args[index + 1];
    if (!option?.startsWith("--") || !allowed.has(option.slice(2))) {
      throw new Error(`unknown option: ${option ?? "<missing>"}`);
    }
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`missing value for ${option}`);
    }
    const name = option.slice(2);
    if (Object.hasOwn(options, name)) {
      throw new Error(`duplicate option: ${option}`);
    }
    options[name] = value;
  }
  return options;
}

function requireOptions(options, names) {
  for (const name of names) {
    if (!options[name]) {
      throw new Error(`missing required option: --${name}`);
    }
  }
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    const detail = result.stderr.trim() || result.stdout.trim() || `exit ${result.status}`;
    throw new Error(`${command} failed: ${detail}`);
  }
  return result.stdout;
}

function readProcessCommand(pid) {
  const result = spawnSync("/bin/ps", ["-p", String(pid), "-o", "command="], {
    encoding: "utf8"
  });
  if (result.error || result.status !== 0) {
    return null;
  }
  const command = result.stdout.trim();
  return command || null;
}

function readPlistValue(plistPath, key) {
  return run("/usr/bin/plutil", ["-extract", key, "raw", "-o", "-", plistPath]).trim();
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function openApp(appPath) {
  const deadline = Date.now() + 3000;
  while (true) {
    const result = spawnSync("/usr/bin/open", [appPath], { encoding: "utf8" });
    if (!result.error && result.status === 0) {
      return;
    }
    if (result.error) {
      throw result.error;
    }
    const detail = result.stderr.trim() || result.stdout.trim() || `exit ${result.status}`;
    if (!shouldRetryOpenFailure(detail) || Date.now() >= deadline) {
      throw new Error(`/usr/bin/open failed: ${detail}`);
    }
    await delay(100);
  }
}

async function stopMatchingProcesses(executablePath) {
  const processes = parseProcessTable(run("/bin/ps", ["-axo", "pid=,command="]));
  const pids = matchingProcessIDs(processes, executablePath);

  for (const pid of pids) {
    if (readProcessCommand(pid) !== executablePath) {
      continue;
    }
    try {
      process.kill(pid, "SIGTERM");
    } catch (error) {
      if (error.code !== "ESRCH") {
        throw error;
      }
    }
  }

  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    const remaining = pids.filter((pid) => readProcessCommand(pid) === executablePath);
    if (remaining.length === 0) {
      return pids.length;
    }
    await delay(50);
  }

  const remaining = pids.filter((pid) => readProcessCommand(pid) === executablePath);
  if (remaining.length > 0) {
    throw new Error(`prior Debug instance did not exit: ${remaining.join(", ")}`);
  }
  return pids.length;
}

async function runDebugApp(options) {
  requireOptions(options, ["repo-root", "app", "executable"]);
  const repoRoot = realpathSync.native(path.resolve(options["repo-root"]));
  const appPath = realpathSync.native(path.resolve(options.app));
  const executablePath = path.join(appPath, "Contents", "MacOS", options.executable);
  const plistPath = path.join(appPath, "Contents", "Info.plist");
  const checkoutID = checkoutIdentity(repoRoot);
  const packagedCheckoutID = readPlistValue(plistPath, "MD2PNGDebugCheckoutID");
  const bundleIdentifier = readPlistValue(plistPath, "CFBundleIdentifier");

  if (packagedCheckoutID !== checkoutID) {
    throw new Error("Debug app checkout identity does not match the current checkout");
  }
  if (!bundleIdentifier.endsWith(`.debug-${checkoutID}`)) {
    throw new Error("Debug app bundle identifier is not scoped to the current checkout");
  }

  const stoppedCount = await stopMatchingProcesses(executablePath);
  await openApp(appPath);
  if (stoppedCount > 0) {
    process.stdout.write(`Replaced ${stoppedCount} prior Debug instance(s) for this checkout.\n`);
  }
}

export async function main(args) {
  const [command, ...optionArgs] = args;
  switch (command) {
  case "identity": {
    const options = parseOptions(optionArgs, ["repo-root"]);
    requireOptions(options, ["repo-root"]);
    process.stdout.write(`${checkoutIdentity(options["repo-root"])}\n`);
    break;
  }
  case "bundle-identifier": {
    const options = parseOptions(optionArgs, ["repo-root", "base"]);
    requireOptions(options, ["repo-root", "base"]);
    process.stdout.write(`${debugBundleIdentifier(
      options.base,
      checkoutIdentity(options["repo-root"])
    )}\n`);
    break;
  }
  case "run": {
    const options = parseOptions(optionArgs, ["repo-root", "app", "executable"]);
    await runDebugApp(options);
    break;
  }
  default:
    throw new Error(`unknown command: ${command ?? "<missing>"}`);
  }
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (invokedPath && import.meta.url === pathToFileURL(invokedPath).href) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`debug-run: ${error.message}\n`);
    process.exitCode = 1;
  });
}
