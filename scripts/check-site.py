#!/usr/bin/env python3

from __future__ import annotations

import json
import plistlib
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
PRODUCTION_ORIGIN = "https://md2png.wbxsh.com"


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[tuple[str, str]] = []
        self.images_without_alt: list[str] = []
        self.canonicals: list[str] = []
        self.alternates: dict[str, str] = {}
        self.json_ld_blocks: list[str] = []
        self._json_ld_parts: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag in {"a", "link"} and values.get("href"):
            self.links.append(("href", values["href"] or ""))
        if tag in {"img", "script"} and values.get("src"):
            self.links.append(("src", values["src"] or ""))
        if tag == "img" and "alt" not in values:
            self.images_without_alt.append(values.get("src") or "<unknown>")
        if tag == "link" and values.get("rel") == "canonical":
            self.canonicals.append(values.get("href") or "")
        if tag == "link" and values.get("rel") == "alternate" and values.get("hreflang"):
            self.alternates[values["hreflang"] or ""] = values.get("href") or ""
        if tag == "script" and values.get("type") == "application/ld+json":
            self._json_ld_parts = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self._json_ld_parts is not None:
            self.json_ld_blocks.append("".join(self._json_ld_parts))
            self._json_ld_parts = None

    def handle_data(self, data: str) -> None:
        if self._json_ld_parts is not None:
            self._json_ld_parts.append(data)


def fail(message: str) -> None:
    print(f"site-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def resolve_local(page: Path, value: str) -> Path | None:
    if not value or value.startswith("#"):
        return None
    parsed = urlsplit(value)
    if parsed.scheme or parsed.netloc:
        return None
    target = SITE / parsed.path.lstrip("/") if parsed.path.startswith("/") else page.parent / parsed.path
    if parsed.path.endswith("/"):
        target /= "index.html"
    return target.resolve()


def check_page(relative_path: str, canonical: str, version: str) -> None:
    page = SITE / relative_path
    parser = PageParser()
    parser.feed(page.read_text(encoding="utf-8"))

    if parser.canonicals != [canonical]:
        fail(f"{relative_path} canonical is {parser.canonicals!r}, expected {canonical!r}")
    expected_alternates = {
        "en": f"{PRODUCTION_ORIGIN}/",
        "zh-Hans": f"{PRODUCTION_ORIGIN}/zh/",
        "x-default": f"{PRODUCTION_ORIGIN}/",
    }
    if parser.alternates != expected_alternates:
        fail(f"{relative_path} language alternates do not match the production routes")
    if parser.images_without_alt:
        fail(f"{relative_path} images missing alt attributes: {parser.images_without_alt}")
    if len(parser.json_ld_blocks) != 1:
        fail(f"{relative_path} must contain exactly one JSON-LD block")

    metadata = json.loads(parser.json_ld_blocks[0])
    if metadata.get("@type") != "SoftwareApplication":
        fail(f"{relative_path} JSON-LD is not a SoftwareApplication")
    if metadata.get("softwareVersion") != version:
        fail(f"{relative_path} advertises version {metadata.get('softwareVersion')}, expected {version}")

    for attribute, value in parser.links:
        target = resolve_local(page, value)
        if target is not None and not target.exists():
            fail(f"{relative_path} has missing local {attribute}: {value}")


def main() -> None:
    with (ROOT / "Info.plist").open("rb") as stream:
        version = plistlib.load(stream)["CFBundleShortVersionString"]

    check_page("index.html", f"{PRODUCTION_ORIGIN}/", version)
    check_page("zh/index.html", f"{PRODUCTION_ORIGIN}/zh/", version)

    not_found_path = SITE / "404.html"
    not_found = not_found_path.read_text(encoding="utf-8")
    if 'name="robots" content="noindex"' not in not_found:
        fail("404.html must remain excluded from search indexes")
    not_found_parser = PageParser()
    not_found_parser.feed(not_found)
    if not_found_parser.images_without_alt:
        fail(f"404.html images missing alt attributes: {not_found_parser.images_without_alt}")
    for attribute, value in not_found_parser.links:
        target = resolve_local(not_found_path, value)
        if target is not None and not target.exists():
            fail(f"404.html has missing local {attribute}: {value}")

    stale_url = "https://guangyya.github.io/md2png/"
    checked_files = [
        SITE / "index.html",
        SITE / "robots.txt",
        SITE / "sitemap.xml",
        SITE / "zh/index.html",
        ROOT / "README.md",
        ROOT / "README.zh-Hans.md",
    ]
    for path in checked_files:
        if stale_url in path.read_text(encoding="utf-8"):
            fail(f"{path.relative_to(ROOT)} still refers to the pre-domain site URL")

    sitemap = ElementTree.parse(SITE / "sitemap.xml")
    namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    locations = {element.text for element in sitemap.findall("s:url/s:loc", namespace)}
    expected_locations = {f"{PRODUCTION_ORIGIN}/", f"{PRODUCTION_ORIGIN}/zh/"}
    if locations != expected_locations:
        fail("sitemap.xml does not contain exactly the English and Chinese canonical URLs")

    robots = (SITE / "robots.txt").read_text(encoding="utf-8")
    if f"Sitemap: {PRODUCTION_ORIGIN}/sitemap.xml" not in robots:
        fail("robots.txt does not advertise the production sitemap")

    print(f"site-check: ok (version {version}, 2 localized pages, custom 404)")


if __name__ == "__main__":
    main()
