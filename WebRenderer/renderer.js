import DOMPurify from "dompurify";
import hljs from "highlight.js/lib/core";
import bash from "highlight.js/lib/languages/bash";
import c from "highlight.js/lib/languages/c";
import cpp from "highlight.js/lib/languages/cpp";
import css from "highlight.js/lib/languages/css";
import go from "highlight.js/lib/languages/go";
import java from "highlight.js/lib/languages/java";
import javascript from "highlight.js/lib/languages/javascript";
import json from "highlight.js/lib/languages/json";
import kotlin from "highlight.js/lib/languages/kotlin";
import markdownLanguage from "highlight.js/lib/languages/markdown";
import objectivec from "highlight.js/lib/languages/objectivec";
import python from "highlight.js/lib/languages/python";
import rust from "highlight.js/lib/languages/rust";
import sql from "highlight.js/lib/languages/sql";
import swift from "highlight.js/lib/languages/swift";
import typescript from "highlight.js/lib/languages/typescript";
import xml from "highlight.js/lib/languages/xml";
import yaml from "highlight.js/lib/languages/yaml";
import MarkdownIt from "markdown-it";
import mermaid from "mermaid";

const syntaxLanguages = {
  bash,
  c,
  cpp,
  css,
  go,
  java,
  javascript,
  json,
  kotlin,
  markdown: markdownLanguage,
  objectivec,
  python,
  rust,
  sql,
  swift,
  typescript,
  xml,
  yaml
};

for (const [name, language] of Object.entries(syntaxLanguages)) {
  hljs.registerLanguage(name, language);
}

const markdown = new MarkdownIt({
  html: false,
  breaks: false,
  linkify: true,
  typographer: true,
  highlight: (source, language) => {
    const normalizedLanguage = language.trim().toLowerCase();
    if (normalizedLanguage && hljs.getLanguage(normalizedLanguage)) {
      return hljs.highlight(source, {
        language: normalizedLanguage,
        ignoreIllegals: true
      }).value;
    }
    return hljs.highlightAuto(source).value;
  }
});

const defaultFence = markdown.renderer.rules.fence.bind(markdown.renderer.rules);
markdown.renderer.rules.fence = (tokens, index, options, env, self) => {
  const language = tokens[index].info.trim().toLowerCase().split(/\s+/, 1)[0];
  if (language === "mermaid") {
    return `<div class="mermaid">${markdown.utils.escapeHtml(tokens[index].content)}</div>`;
  }
  return defaultFence(tokens, index, options, env, self);
};

// Rendering an external image would leak its URL (and potentially message data)
// to the network. Show a readable placeholder instead.
markdown.renderer.rules.image = (tokens, index) => {
  const token = tokens[index];
  const alt = token.content || "image";
  return `<span class="blocked-image">[Image: ${markdown.utils.escapeHtml(alt)}]</span>`;
};

mermaid.initialize({
  startOnLoad: false,
  securityLevel: "strict",
  theme: "neutral",
  fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
  flowchart: { htmlLabels: false, useMaxWidth: false },
  sequence: { useMaxWidth: false },
  gantt: {
    useMaxWidth: false,
    useWidth: 1200,
    leftPadding: 190,
    rightPadding: 40,
    topPadding: 60,
    gridLineStartPadding: 45,
    barHeight: 24,
    barGap: 6,
    fontSize: 13,
    sectionFontSize: 13
  }
});

function measurement() {
  const card = document.getElementById("card");
  return {
    width: Math.ceil(Math.max(card.scrollWidth, card.getBoundingClientRect().width)),
    height: Math.ceil(Math.max(card.scrollHeight, card.getBoundingClientRect().height))
  };
}

window.renderMarkdown = async (source) => {
  const card = document.getElementById("card");
  card.innerHTML = DOMPurify.sanitize(markdown.render(source), {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ["style", "iframe", "object", "embed"]
  });

  const diagrams = card.querySelectorAll(".mermaid");
  if (diagrams.length > 0) {
    await mermaid.run({ nodes: diagrams, suppressErrors: false });
  }

  await document.fonts.ready;
  return measurement();
};

window.measureRenderedContent = measurement;
