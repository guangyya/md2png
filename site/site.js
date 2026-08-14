(() => {
  const root = document.documentElement;
  const localeButtons = document.querySelectorAll("[data-locale-button]");

  function setLocale(locale, remember = true) {
    const nextLocale = locale === "zh" ? "zh" : "en";
    root.lang = nextLocale === "zh" ? "zh-Hans" : "en";
    root.dataset.locale = nextLocale;

    document.querySelectorAll("[data-en][data-zh]").forEach((element) => {
      element.textContent = element.dataset[nextLocale];
    });

    document.querySelectorAll("[data-en-label][data-zh-label]").forEach((element) => {
      element.setAttribute("aria-label", element.dataset[`${nextLocale}Label`]);
    });

    document.querySelectorAll("[data-en-alt][data-zh-alt]").forEach((element) => {
      element.setAttribute("alt", element.dataset[`${nextLocale}Alt`]);
    });

    localeButtons.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.localeButton === nextLocale));
    });

    if (nextLocale === "zh") {
      document.title = "md2png — 复制 Markdown，粘贴漂亮 PNG";
      document.querySelector('meta[name="description"]').content = "在 Mac 上把剪贴板 Markdown 转为精美 PNG——全程本地，保护隐私。";
    } else {
      document.title = "md2png — Markdown in. Polished PNG out.";
      document.querySelector('meta[name="description"]').content = "Turn clipboard Markdown into a polished PNG on your Mac—locally and privately.";
    }

    if (remember) {
      try {
        window.localStorage.setItem("md2png-locale", nextLocale);
      } catch (_) {
        // Language still works when storage is unavailable.
      }
    }
  }

  localeButtons.forEach((button) => {
    button.addEventListener("click", () => setLocale(button.dataset.localeButton));
  });

  let preferredLocale;
  try {
    preferredLocale = window.localStorage.getItem("md2png-locale");
  } catch (_) {
    preferredLocale = null;
  }

  if (!preferredLocale) {
    preferredLocale = navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
  }

  setLocale(preferredLocale, false);
  document.querySelector("#year").textContent = String(new Date().getFullYear());
})();
