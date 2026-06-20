import { Controller } from "@hotwired/stimulus";

// Client-side-only guide variables. Authors declare an input with the
// `:::var name="x"` block shortcode and reference it inline with
// `::var-ref[x]` (verbatim) or `::var-slug[x]` (sluggified). Values never
// leave the browser: they're stored per-mission in localStorage and painted
// into the reference spans here, so the server-rendered guide HTML stays
// cacheable per-content.
export default class extends Controller {
  static values = { missionSlug: String };

  connect() {
    this.variables = this.load();
    this.hydrate();
  }

  update(event) {
    const input = event.target;
    const name = input.dataset.guideVarInput;
    if (input.value.trim() === "") {
      delete this.variables[name];
    } else {
      this.variables[name] = input.value;
    }
    this.persist();
    this.syncInputs(name, input);
    this.applyRefs(name);
  }

  hydrate() {
    this.element.querySelectorAll("[data-guide-var-input]").forEach((input) => {
      const value = this.variables[input.dataset.guideVarInput];
      if (value !== undefined) input.value = value;
    });
    this.applyRefs();
  }

  // Same variable declared in more than one section — keep the inputs as one.
  syncInputs(name, source) {
    this.element
      .querySelectorAll(`[data-guide-var-input="${CSS.escape(name)}"]`)
      .forEach((input) => {
        if (input !== source) input.value = source.value;
      });
  }

  applyRefs(name = null) {
    this.element.querySelectorAll("[data-guide-var-ref]").forEach((ref) => {
      const refName = ref.dataset.guideVarRef;
      if (name !== null && refName !== name) return;

      const value = (this.variables[refName] || "").trim();
      const display =
        ref.dataset.guideVarMode === "slug" ? this.slugify(value) : value;
      const empty = display === "";
      ref.textContent = empty ? refName : display;
      ref.classList.toggle("guide-var-ref--empty", empty);
    });
  }

  // Lowercase, spaces to dashes, punctuation removed.
  slugify(value) {
    return value
      .toLowerCase()
      .replace(/\s+/g, "-")
      .replace(/[^a-z0-9-]/g, "")
      .replace(/-+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  storageKey() {
    return `stardance:v1:mission-guide-vars:${this.missionSlugValue}`;
  }

  load() {
    try {
      const parsed = JSON.parse(window.localStorage.getItem(this.storageKey()));
      return parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      return {};
    }
  }

  persist() {
    try {
      window.localStorage.setItem(
        this.storageKey(),
        JSON.stringify(this.variables),
      );
    } catch {}
  }
}
