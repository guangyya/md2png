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
import renderThemeManifest from "../Sources/MD2PNG/Resources/Themes/manifest.json";

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
  const token = tokens[index];
  const language = token.info.trim().toLowerCase().split(/\s+/, 1)[0];
  if (language === "mermaid") {
    env.mermaidCount = (env.mermaidCount || 0) + 1;
    const sourceLine = Array.isArray(token.map) ? token.map[0] + 2 : null;
    const lineAttribute = sourceLine === null ? "" : ` data-md2png-line="${sourceLine}"`;
    const lineCount = Math.max(1, token.content.replace(/\n$/, "").split("\n").length);
    return `<div class="mermaid" data-md2png-diagram="${env.mermaidCount}" data-md2png-lines="${lineCount}"${lineAttribute}>${markdown.utils.escapeHtml(token.content)}</div>`;
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

const mermaidLayout = {
  startOnLoad: false,
  securityLevel: "strict",
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
};

const supportedThemeSchemaVersion = 1;
const themeStylesheetPattern = /^Themes\/[a-z0-9-]+\/theme\.css$/;
if (renderThemeManifest.schemaVersion !== supportedThemeSchemaVersion) {
  throw new Error("Unsupported render theme manifest");
}

const renderThemes = new Map();
for (const theme of renderThemeManifest.themes) {
  if (!/^[A-Za-z][A-Za-z0-9]*$/.test(theme.id)
      || !themeStylesheetPattern.test(theme.stylesheet)
      || renderThemes.has(theme.id)) {
    throw new Error("Invalid render theme manifest");
  }
  renderThemes.set(theme.id, theme);
}
if (renderThemeManifest.themes[0]?.id !== "cleanLight") {
  throw new Error("Render theme manifest is missing the default theme");
}

function selectRenderTheme(name) {
  return renderThemes.has(name) ? name : "cleanLight";
}

function loadThemeStylesheet(theme) {
  const stylesheet = document.getElementById("render-theme-stylesheet");
  if (!(stylesheet instanceof HTMLLinkElement)) {
    return Promise.reject(new Error("Render theme stylesheet is unavailable"));
  }
  if (stylesheet.dataset.themeStylesheet === theme.stylesheet) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const previousStylesheet = stylesheet.dataset.themeStylesheet;
    const cleanup = () => {
      stylesheet.onload = null;
      stylesheet.onerror = null;
    };
    stylesheet.onload = () => {
      stylesheet.dataset.themeStylesheet = theme.stylesheet;
      cleanup();
      resolve();
    };
    stylesheet.onerror = () => {
      cleanup();
      stylesheet.href = previousStylesheet;
      reject(new Error("Render theme stylesheet could not be loaded"));
    };
    stylesheet.href = theme.stylesheet;
  });
}

function measurement() {
  const card = document.getElementById("card");
  return {
    width: Math.ceil(Math.max(card.scrollWidth, card.getBoundingClientRect().width)),
    height: Math.ceil(Math.max(card.scrollHeight, card.getBoundingClientRect().height))
  };
}

function verticalRange(element, cardTop, contentHeight) {
  const bounds = element.getBoundingClientRect();
  const start = Math.max(0, Math.ceil(bounds.top - cardTop));
  const end = Math.min(contentHeight, Math.floor(bounds.bottom - cardTop));
  return end > start ? [start, end] : null;
}

function splitGeometry() {
  const card = document.getElementById("card");
  const { height: contentHeight } = measurement();
  const cardTop = card.getBoundingClientRect().top;
  const preferredBreakOffsets = new Set();
  const protectedRanges = [];

  for (const element of card.querySelectorAll(":scope > *, li, tr")) {
    const range = verticalRange(element, cardTop, contentHeight);
    if (range) {
      const offset = element.matches("h1, h2, h3, h4, h5, h6")
        ? range[0]
        : range[1];
      if (offset > 0 && offset < contentHeight) {
        preferredBreakOffsets.add(offset);
      }
    }
  }
  for (const element of card.querySelectorAll("pre, .mermaid, tr")) {
    const range = verticalRange(element, cardTop, contentHeight);
    if (range) {
      protectedRanges.push(range);
    }
  }

  return {
    contentHeight,
    preferredBreakOffsets: [...preferredBreakOffsets].sort((left, right) => left - right),
    protectedRanges
  };
}

function positiveLineNumber(value) {
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 ? number : null;
}

function mermaidErrorLine(error) {
  const candidates = [
    error?.hash?.loc?.first_line,
    error?.hash?.line,
    error?.location?.start?.line,
    error?.line,
    error?.lineNumber
  ];
  for (const candidate of candidates) {
    const line = positiveLineNumber(candidate);
    if (line !== null) {
      return line;
    }
  }
  const text = [error?.str, error?.message]
    .filter((value) => typeof value === "string")
    .join(" ");
  const match = text.match(/(?:on|at)?\s*line\s+(\d+)/i);
  if (match) {
    return positiveLineNumber(match[1]);
  }
  return null;
}

function mermaidFailureKind(error) {
  const name = typeof error?.name === "string" ? error.name : "";
  const message = typeof error?.message === "string" ? error.message : "";
  return /diagram type|unknowndiagram/i.test(`${name} ${message}`)
    ? "mermaid_diagram_type"
    : "mermaid_syntax";
}

function mermaidFailure(error, diagram) {
  const kind = mermaidFailureKind(error);
  const diagramNumber = positiveLineNumber(diagram.dataset.md2pngDiagram) || 1;
  const diagramStartLine = positiveLineNumber(diagram.dataset.md2pngLine);
  const diagramLineCount = positiveLineNumber(diagram.dataset.md2pngLines);
  const reportedDiagramLine = mermaidErrorLine(error);
  const diagramLine = reportedDiagramLine === null || diagramLineCount === null
    ? reportedDiagramLine
    : Math.min(reportedDiagramLine, diagramLineCount);
  let sourceLine = null;
  if (kind === "mermaid_diagram_type" && diagramStartLine !== null) {
    sourceLine = diagramStartLine;
  } else if (diagramStartLine !== null && diagramLine !== null) {
    sourceLine = diagramStartLine + diagramLine - 1;
  } else if (diagramStartLine !== null) {
    sourceLine = diagramStartLine;
  }
  return {
    ok: false,
    kind,
    diagramNumber,
    ...(sourceLine === null ? {} : { sourceLine })
  };
}

window.renderMarkdown = async (source, requestedTheme) => {
  const themeName = selectRenderTheme(requestedTheme);
  const theme = renderThemes.get(themeName);
  await loadThemeStylesheet(theme);
  document.documentElement.dataset.renderTheme = themeName;
  mermaid.initialize({
    ...mermaidLayout,
    theme: theme.mermaidTheme,
    ...(theme.mermaidVariables ? { themeVariables: theme.mermaidVariables } : {})
  });

  const card = document.getElementById("card");
  const renderEnvironment = { mermaidCount: 0 };
  card.innerHTML = DOMPurify.sanitize(markdown.render(source, renderEnvironment), {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ["style", "iframe", "object", "embed"]
  });

  const diagrams = card.querySelectorAll(".mermaid");
  for (const diagram of diagrams) {
    try {
      await mermaid.parse(diagram.textContent || "");
    } catch (error) {
      return mermaidFailure(error, diagram);
    }
  }
  if (diagrams.length > 0) {
    try {
      await mermaid.run({ nodes: diagrams, suppressErrors: false });
    } catch (error) {
      return mermaidFailure(error, diagrams[0]);
    }
  }

  await document.fonts.ready;
  return { ok: true, ...measurement() };
};

window.measureRenderedContent = measurement;
window.measureRenderedContentForSplitting = splitGeometry;
