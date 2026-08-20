#!/usr/bin/env python3

from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path
from string import Template
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "site-src"
SITE = ROOT / "site"
TEMPLATE = Template((SOURCE / "index.html").read_text(encoding="utf-8"))
PRODUCTION_ORIGIN = "https://md2png.wbxsh.com"

LOCALES = {
    "en": {
        "source": SOURCE / "locales/en.json",
        "output": SITE / "index.html",
        "html_lang": "en",
        "data_locale": "en",
        "canonical": f"{PRODUCTION_ORIGIN}/",
        "asset_prefix": "",
        "english_href": "./",
        "chinese_href": "zh/",
        "english_current": ' aria-current="page"',
        "chinese_current": "",
    },
    "zh-Hans": {
        "source": SOURCE / "locales/zh-Hans.json",
        "output": SITE / "zh/index.html",
        "html_lang": "zh-Hans",
        "data_locale": "zh",
        "canonical": f"{PRODUCTION_ORIGIN}/zh/",
        "asset_prefix": "../",
        "english_href": "../",
        "chinese_href": "./",
        "english_current": "",
        "chinese_current": ' aria-current="page"',
    },
}


def escaped(value: Any) -> str:
    return html.escape(str(value), quote=True)


def render_list(items: list[str], template: str) -> str:
    return "\n".join(template.format(item=escaped(item)) for item in items)


def render_page(locale: str) -> str:
    config = LOCALES[locale]
    content = json.loads(config["source"].read_text(encoding="utf-8"))

    nav_links = "\n".join(
        f'          <a href="{escaped(item["href"])}">{escaped(item["label"])}</a>'
        for item in content["navigation"]["links"]
    )
    trust_items = render_list(
        content["trust"]["items"],
        '          <p><span class="trust-mark" aria-hidden="true">●</span><span>{item}</span></p>',
    )
    steps = "\n".join(
        """            <li>
              <span class="step-number">{number}</span>
              <div><h3>{title}</h3><p>{description}</p></div>
              <kbd>{key}</kbd>
            </li>""".format(**{key: escaped(value) for key, value in item.items()})
        for item in content["how"]["steps"]
    )
    features = "\n".join(
        """            <article class="feature-card">
              <div class="feature-meta"><span>{number}</span><span>{label}</span></div>
              <h3>{title}</h3>
              <p>{description}</p>
              <ul class="feature-tags" aria-label="{tags_aria}">{tags}</ul>
            </article>""".format(
            number=escaped(item["number"]),
            label=escaped(item["label"]),
            title=escaped(item["title"]),
            description=escaped(item["description"]),
            tags_aria=escaped(item["tags_aria"]),
            tags="".join(f"<li>{escaped(tag)}</li>" for tag in item["tags"]),
        )
        for item in content["features"]["items"]
    )
    format_items = "\n".join(
        f'              <li><span class="format-icon" aria-hidden="true">{escaped(item["icon"])}</span><span>{escaped(item["text"])}</span></li>'
        for item in content["showcase"]["formats"]
    )
    install_steps = "\n".join(
        f'              <li><span>{index}</span><p><strong>{escaped(item["action"])}</strong> {escaped(item["detail"])}</p></li>'
        for index, item in enumerate(content["install"]["steps"], start=1)
    )
    faq_items = "\n".join(
        """              <details{open_attribute}>
                <summary>{summary}</summary>
                <p>{body}</p>
              </details>""".format(
            open_attribute=" open" if index == 0 else "",
            summary=escaped(item["summary"]),
            body=escaped(item["body"]),
        )
        for index, item in enumerate(content["faq"]["items"])
    )
    json_ld = json.dumps(
        {
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            "name": "md2png",
            "description": content["meta"]["json_description"],
            "url": config["canonical"],
            "downloadUrl": "https://github.com/guangyya/md2png/releases/latest/download/md2png-latest.dmg",
            "operatingSystem": content["meta"]["operating_system"],
            "applicationCategory": "UtilitiesApplication",
            "isAccessibleForFree": True,
            "license": "https://github.com/guangyya/md2png/blob/main/LICENSE",
            "codeRepository": "https://github.com/guangyya/md2png",
            "image": f"{PRODUCTION_ORIGIN}/assets/og.png",
            "inLanguage": locale,
            "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        },
        ensure_ascii=False,
        indent=8,
    )

    values: dict[str, str] = {
        key: escaped(value) for key, value in content["text"].items()
    }
    values.update({
        "html_lang": config["html_lang"],
        "data_locale": config["data_locale"],
        "canonical": config["canonical"],
        "asset_prefix": config["asset_prefix"],
        "english_href": config["english_href"],
        "chinese_href": config["chinese_href"],
        "english_current": config["english_current"],
        "chinese_current": config["chinese_current"],
        "meta_description": escaped(content["meta"]["description"]),
        "og_locale": escaped(content["meta"]["og_locale"]),
        "og_locale_alternate": escaped(content["meta"]["og_locale_alternate"]),
        "title": escaped(content["meta"]["title"]),
        "og_description": escaped(content["meta"]["og_description"]),
        "og_image_alt": escaped(content["meta"]["og_image_alt"]),
        "twitter_description": escaped(content["meta"]["twitter_description"]),
        "json_ld": json_ld,
        "nav_links": nav_links,
        "source_sample": escaped(content["hero"]["source_sample"]),
        "trust_items": trust_items,
        "steps": steps,
        "features": features,
        "format_items": format_items,
        "install_steps": install_steps,
        "faq_items": faq_items,
    })
    return TEMPLATE.substitute(values).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the localized static Pages routes")
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when committed Pages output differs from the shared sources",
    )
    args = parser.parse_args()

    stale: list[Path] = []
    for locale, config in LOCALES.items():
        output = config["output"]
        rendered = render_page(locale)
        if args.check:
            if not output.is_file() or output.read_text(encoding="utf-8") != rendered:
                stale.append(output)
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(rendered, encoding="utf-8")

    if stale:
        relative_paths = ", ".join(str(path.relative_to(ROOT)) for path in stale)
        print(
            f"site-generate: stale output: {relative_paths}; run scripts/generate-site.py",
            file=sys.stderr,
        )
        raise SystemExit(1)
    print("site-generate: outputs are current" if args.check else "site-generate: generated 2 localized pages")


if __name__ == "__main__":
    main()
