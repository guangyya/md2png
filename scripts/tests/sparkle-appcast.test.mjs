import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { validateAppcast, validateSignedAppcast } from "../sparkle-appcast.mjs";

const version = "0.7.0";
const build = "7";
const repository = "guangyya/md2png";
const archiveName = `md2png-${version}-macOS-arm64-developer-id.zip`;
const repoRoot = path.resolve(new URL("../..", import.meta.url).pathname);

function fixture({
  includeHistory = false,
  hardwareRequirements = "arm64",
  channel = "",
} = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "md2png-appcast-test-"));
  const archive = path.join(directory, archiveName);
  const file = path.join(directory, "appcast.xml");
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyDER = publicKey.export({ format: "der", type: "spki" });
  const publicKeyBase64 = publicKeyDER.subarray(publicKeyDER.length - 32).toString("base64");
  const archiveData = Buffer.from("signed app archive");
  fs.writeFileSync(archive, archiveData);
  const archiveSignature = crypto.sign(null, archiveData, privateKey).toString("base64");
  const historicalVersion = "0.6.0";
  const historicalArchiveName = `md2png-${historicalVersion}-macOS-arm64-developer-id.zip`;
  const historicalSignature = crypto.sign(
    null,
    Buffer.from("historical archive"),
    privateKey,
  ).toString("base64");
  const historicalItem = includeHistory ? `
    <item>
      <title>${historicalVersion}</title>
      <link>https://github.com/${repository}/releases/tag/v${historicalVersion}</link>
      <description sparkle:descriptionFormat="plain-text">Historical release notes</description>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <enclosure url="https://github.com/${repository}/releases/download/v${historicalVersion}/${historicalArchiveName}" length="18" type="application/octet-stream" sparkle:version="6" sparkle:shortVersionString="${historicalVersion}" sparkle:edSignature="${historicalSignature}" />
    </item>` : "";
  const content = Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>md2png</title>
    <item>
      <title>${version}</title>
      <link>https://github.com/${repository}/releases/tag/v${version}</link>
      <description sparkle:descriptionFormat="plain-text">Release notes</description>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>${hardwareRequirements}</sparkle:hardwareRequirements>
      ${channel ? `<sparkle:channel>${channel}</sparkle:channel>` : ""}
      <enclosure url="https://github.com/${repository}/releases/download/v${version}/${archiveName}" length="${archiveData.length}" type="application/octet-stream" sparkle:version="${build}" sparkle:shortVersionString="${version}" sparkle:edSignature="${archiveSignature}" />
    </item>${historicalItem}
  </channel>
</rss>
`);
  const feedSignature = crypto.sign(null, content, privateKey).toString("base64");
  fs.writeFileSync(file, Buffer.concat([
    content,
    Buffer.from(`<!-- sparkle-signatures:\nedSignature: ${feedSignature}\nlength: ${content.length}\n-->\n`),
  ]));
  return { directory, file, archive, publicKey: publicKeyBase64 };
}

test("validates both signed feed metadata and the signed update archive", (context) => {
  const input = fixture();
  context.after(() => fs.rmSync(input.directory, { recursive: true, force: true }));
  assert.equal(validateAppcast({ ...input, version, build, repository }), true);
});

test("rejects feed or archive tampering", (context) => {
  const input = fixture();
  context.after(() => fs.rmSync(input.directory, { recursive: true, force: true }));
  fs.appendFileSync(input.file, "tampered");
  assert.throws(
    () => validateAppcast({ ...input, version, build, repository }),
    /signature block/,
  );

  const second = fixture();
  context.after(() => fs.rmSync(second.directory, { recursive: true, force: true }));
  fs.appendFileSync(second.archive, "tampered");
  assert.throws(
    () => validateAppcast({ ...second, version, build, repository }),
    /archive length|archive signature/,
  );
});

test("preserves a bounded signed history while validating the current archive", (context) => {
  const input = fixture({ includeHistory: true });
  context.after(() => fs.rmSync(input.directory, { recursive: true, force: true }));

  assert.equal(validateSignedAppcast(input), true);
  assert.equal(validateAppcast({ ...input, version, build, repository }), true);
});

test("rejects incompatible hardware and non-stable feed channels", (context) => {
  const incompatible = fixture({ hardwareRequirements: "x86_64" });
  context.after(() => fs.rmSync(incompatible.directory, { recursive: true, force: true }));
  assert.throws(
    () => validateAppcast({ ...incompatible, version, build, repository }),
    /compatibility metadata/,
  );

  const nightly = fixture({ channel: "nightly" });
  context.after(() => fs.rmSync(nightly.directory, { recursive: true, force: true }));
  assert.throws(
    () => validateAppcast({ ...nightly, version, build, repository }),
    /must not declare an update channel/,
  );
});

test("generator authenticates and carries the previous feed into the next release", () => {
  const generator = fs.readFileSync(
    path.join(repoRoot, "scripts/generate-appcast.sh"),
    "utf8",
  );
  assert.match(generator, /releases\/latest\/download\/appcast\.xml/);
  assert.match(generator, /validate-feed/);
  assert.match(generator, /--maximum-versions 3/);
  assert.match(generator, /--full-release-notes-url/);
  assert.match(generator, /refusing to truncate update history/);
});
