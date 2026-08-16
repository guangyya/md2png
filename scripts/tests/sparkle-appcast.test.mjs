import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { validateAppcast } from "../sparkle-appcast.mjs";

const version = "0.7.0";
const build = "7";
const repository = "guangyya/md2png";
const archiveName = `md2png-${version}-macOS-arm64-developer-id.zip`;

function fixture() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "md2png-appcast-test-"));
  const archive = path.join(directory, archiveName);
  const file = path.join(directory, "appcast.xml");
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyDER = publicKey.export({ format: "der", type: "spki" });
  const publicKeyBase64 = publicKeyDER.subarray(publicKeyDER.length - 32).toString("base64");
  const archiveData = Buffer.from("signed app archive");
  fs.writeFileSync(archive, archiveData);
  const archiveSignature = crypto.sign(null, archiveData, privateKey).toString("base64");
  const content = Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>md2png</title>
    <item>
      <title>${version}</title>
      <link>https://github.com/${repository}/releases/tag/v${version}</link>
      <description sparkle:descriptionFormat="plain-text">Release notes</description>
      <enclosure url="https://github.com/${repository}/releases/download/v${version}/${archiveName}" length="${archiveData.length}" type="application/octet-stream" sparkle:version="${build}" sparkle:shortVersionString="${version}" sparkle:edSignature="${archiveSignature}" />
    </item>
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
