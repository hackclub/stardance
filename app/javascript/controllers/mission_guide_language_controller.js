import { Controller } from "@hotwired/stimulus";

// Language picker for the guide. Reloads with ?language=X (the page is
// server-rendered per language) and remembers the choice per-mission in
// localStorage. Explicit URL queries always beat the stored preference.
export default class extends Controller {
  static targets = ["option"];
  static values = {
    missionSlug: String,
    currentLanguage: String,
    availableLanguages: Array,
  };

  connect() {
    this.optionTargets.forEach((opt) => {
      const lang = opt.dataset.language;
      opt.classList.toggle(
        "mission-guide__lang-toggle-option--active",
        lang === this.currentLanguageValue,
      );
      opt.setAttribute(
        "aria-pressed",
        lang === this.currentLanguageValue ? "true" : "false",
      );
    });

    this.maybeHonorPreference();
  }

  storageKey() {
    return `stardance:v1:mission-guide-lang:${this.missionSlugValue}`;
  }

  maybeHonorPreference() {
    try {
      const url = new URL(window.location.href);
      if (url.searchParams.has("language")) return;

      const stored = window.localStorage.getItem(this.storageKey());
      if (!stored || stored === this.currentLanguageValue) return;
      if (!this.availableLanguagesValue.includes(stored)) return;

      url.searchParams.set("language", stored);
      window.location.replace(url.toString());
    } catch {}
  }

  select(event) {
    event.preventDefault();
    const lang = event.currentTarget.dataset.language;
    if (!lang || lang === this.currentLanguageValue) return;

    try {
      window.localStorage.setItem(this.storageKey(), lang);
    } catch {}

    const url = new URL(window.location.href);
    url.searchParams.set("language", lang);
    url.hash = "";
    window.location.assign(url.toString());
  }
}
