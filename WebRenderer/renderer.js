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

const renderThemes = {
  cleanLight: {
    mermaidTheme: "neutral"
  },
  warmPaper: {
    mermaidTheme: "base",
    mermaid: {
      background: "#faf8f3",
      primaryColor: "#ece7de",
      primaryTextColor: "#39342d",
      primaryBorderColor: "#a88f68",
      secondaryColor: "#e7e5c7",
      secondaryTextColor: "#3d3428",
      secondaryBorderColor: "#87925d",
      tertiaryColor: "#f4d8bc",
      tertiaryTextColor: "#3d3428",
      tertiaryBorderColor: "#bd7a4b",
      lineColor: "#766650",
      textColor: "#39342d",
      noteBkgColor: "#f6e5b8",
      noteTextColor: "#3d3428",
      noteBorderColor: "#b58a3c",
      actorBkg: "#ece7de",
      actorBorder: "#a88f68",
      actorTextColor: "#3d3428",
      actorLineColor: "#a88f68",
      signalColor: "#766650",
      signalTextColor: "#3d3428",
      labelBoxBkgColor: "#ece7de",
      labelBoxBorderColor: "#a88f68",
      labelTextColor: "#3d3428",
      loopTextColor: "#3d3428",
      activationBkgColor: "#e7e5c7",
      activationBorderColor: "#87925d",
      sequenceNumberColor: "#faf8f3",
      sectionBkgColor: "#e7e5c7",
      altSectionBkgColor: "#ece7de",
      sectionBkgColor2: "#f4d8bc",
      taskBorderColor: "#87925d",
      taskBkgColor: "#e7e5c7",
      taskTextColor: "#3d3428",
      taskTextDarkColor: "#3d3428",
      taskTextOutsideColor: "#3d3428",
      activeTaskBorderColor: "#a56a32",
      activeTaskBkgColor: "#f4d8bc",
      doneTaskBkgColor: "#dce4c4",
      doneTaskBorderColor: "#71804f",
      critBorderColor: "#a6463d",
      critBkgColor: "#efd0c5",
      todayLineColor: "#a6463d",
      gridColor: "#d6ccbd"
    }
  },
  dark: {
    mermaidTheme: "base",
    mermaid: {
      darkMode: true,
      background: "#0d1117",
      primaryColor: "#21262d",
      primaryTextColor: "#e6edf3",
      primaryBorderColor: "#6e7681",
      secondaryColor: "#1f3a5f",
      secondaryTextColor: "#e6edf3",
      secondaryBorderColor: "#58a6ff",
      tertiaryColor: "#4b3a18",
      tertiaryTextColor: "#e6edf3",
      tertiaryBorderColor: "#d29922",
      lineColor: "#8b949e",
      textColor: "#e6edf3",
      noteBkgColor: "#4b3a18",
      noteTextColor: "#f0f6fc",
      noteBorderColor: "#d29922",
      actorBkg: "#21262d",
      actorBorder: "#6e7681",
      actorTextColor: "#e6edf3",
      actorLineColor: "#6e7681",
      signalColor: "#8b949e",
      signalTextColor: "#e6edf3",
      labelBoxBkgColor: "#21262d",
      labelBoxBorderColor: "#6e7681",
      labelTextColor: "#e6edf3",
      loopTextColor: "#e6edf3",
      activationBkgColor: "#1f3a5f",
      activationBorderColor: "#58a6ff",
      sequenceNumberColor: "#0d1117",
      sectionBkgColor: "#1f3a5f",
      altSectionBkgColor: "#161b22",
      sectionBkgColor2: "#4b3a18",
      taskBorderColor: "#58a6ff",
      taskBkgColor: "#1f3a5f",
      taskTextColor: "#e6edf3",
      taskTextDarkColor: "#e6edf3",
      taskTextOutsideColor: "#e6edf3",
      activeTaskBorderColor: "#d29922",
      activeTaskBkgColor: "#4b3a18",
      doneTaskBkgColor: "#1b4721",
      doneTaskBorderColor: "#3fb950",
      critBorderColor: "#f85149",
      critBkgColor: "#5a1e23",
      todayLineColor: "#f85149",
      gridColor: "#30363d"
    }
  }
};

function selectRenderTheme(name) {
  return Object.hasOwn(renderThemes, name) ? name : "cleanLight";
}

function measurement() {
  const card = document.getElementById("card");
  return {
    width: Math.ceil(Math.max(card.scrollWidth, card.getBoundingClientRect().width)),
    height: Math.ceil(Math.max(card.scrollHeight, card.getBoundingClientRect().height))
  };
}

window.renderMarkdown = async (source, requestedTheme) => {
  const themeName = selectRenderTheme(requestedTheme);
  const theme = renderThemes[themeName];
  document.documentElement.dataset.renderTheme = themeName;
  mermaid.initialize({
    ...mermaidLayout,
    theme: theme.mermaidTheme,
    ...(theme.mermaid ? { themeVariables: theme.mermaid } : {})
  });

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
