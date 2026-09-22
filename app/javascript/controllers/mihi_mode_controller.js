import { Controller } from "@hotwired/stimulus";

const SKIP_TEXT =
  "script, style, noscript, textarea, [contenteditable], [data-mihi-mode-ignore]";
const LABEL_ATTRIBUTES = ["placeholder", "title", "alt", "aria-label"];
const mihify = (text) =>
  text.replace(/[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}]+)*/gu, "mihi");

// Presentation only: preserve markup, link destinations, and form data.
export default class extends Controller {
  static targets = ["toggle"];
  static values = { imageUrl: String, activationUrl: String };

  connect() {
    this.originals = new Map();
    this.attributes = new Map();
    this.images = new Set();
    this.observer = new MutationObserver(() => this.refresh());
    this.beforeCache = () => this.restore();
    document.addEventListener("turbo:before-cache", this.beforeCache);
    this.enabled = false;
    this.updateButtons();
  }

  activate() {
    if (this.enabled) return;
    this.enabled = true;
    this.refresh();
    this.updateButtons();
    fetch(this.activationUrlValue, {
      method: "POST",
      credentials: "same-origin",
      keepalive: true,
      headers: {
        "X-CSRF-Token":
          document.querySelector('meta[name="csrf-token"]')?.content || "",
        Accept: "application/json",
      },
    }).catch(() => {
      // Analytics failure must not prevent the visual effect.
    });
  }

  toggleTargetConnected() {
    this.updateButtons();
  }

  updateButtons() {
    this.toggleTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(Boolean(this.enabled)));
      button.disabled = Boolean(this.enabled);
      button.querySelector(".action-btn__label").textContent = this.enabled
        ? "u stupid #getmihid"
        : "free 10,000 stardust hack *LEGIT* 2026 (WORKING)";
    });
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache);
    this.restore();
  }

  refresh() {
    this.observer.disconnect();
    this.replaceImages();
    for (const map of [this.originals, this.attributes]) {
      for (const node of map.keys()) {
        if (!this.element.contains(node)) map.delete(node);
      }
    }

    const walker = document.createTreeWalker(
      this.element,
      NodeFilter.SHOW_TEXT,
    );
    let node;
    while ((node = walker.nextNode())) {
      if (node.parentElement.closest(SKIP_TEXT) || !node.textContent.trim())
        continue;

      // An option without an explicit value submits its text. Preserve that value.
      const option = node.parentElement.closest("option");
      if (option && !option.hasAttribute("value")) {
        this.rememberAttribute(option, "value");
        option.setAttribute("value", option.value);
      }

      const replacement = mihify(node.textContent);
      if (!this.originals.has(node) || node.textContent !== replacement) {
        this.originals.set(node, node.textContent);
      }
      if (node.textContent !== replacement) node.textContent = replacement;
    }

    this.element
      .querySelectorAll("[placeholder], [title], [alt], [aria-label]")
      .forEach((element) => {
        if (element.closest(SKIP_TEXT)) return;
        for (const name of LABEL_ATTRIBUTES) {
          const value = element.getAttribute(name);
          if (!value?.trim() || value === mihify(value)) continue;
          this.rememberAttribute(element, name);
          element.setAttribute(name, mihify(value));
        }
      });

    this.observer.observe(this.element, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
      attributeFilter: [...LABEL_ATTRIBUTES, "src", "srcset"],
    });
  }

  replaceImages() {
    const image = `url(${JSON.stringify(this.imageUrlValue)})`;
    this.element.style.setProperty("--mihi-portrait", image);
    for (const element of this.images) {
      if (!this.element.contains(element)) this.images.delete(element);
    }

    this.element.querySelectorAll("*").forEach((element) => {
      if (element.closest("script, style, [data-mihi-mode-ignore]")) return;
      if (this.images.has(element)) return;
      if (element.matches("img")) {
        const style = getComputedStyle(element);
        this.rememberAttribute(element, "style");
        element.style.width = style.width;
        element.style.height = style.height;
        element.style.objectFit = "fill";
        // CSS replacement preserves src/srcset, picture sources, and their data.
        element.style.content = image;
        this.images.add(element);
        return;
      }

      const style = getComputedStyle(element);
      if (
        element.matches("svg, [role='img']") ||
        /url\(/.test(style.backgroundImage) ||
        /url\(/.test(style.maskImage)
      ) {
        this.rememberAttribute(element, "data-mihi-image");
        element.setAttribute("data-mihi-image", "true");
        this.images.add(element);
      }
      for (const pseudo of ["before", "after"]) {
        const decoration = getComputedStyle(element, `::${pseudo}`);
        if (
          /url\(/.test(decoration.backgroundImage) ||
          /url\(/.test(decoration.maskImage)
        ) {
          this.rememberAttribute(element, `data-mihi-${pseudo}`);
          element.setAttribute(`data-mihi-${pseudo}`, "true");
          this.images.add(element);
        }
      }
    });
  }

  rememberAttribute(element, name) {
    if (!this.attributes.has(element)) this.attributes.set(element, new Map());
    this.attributes.get(element).set(name, element.getAttribute(name));
  }

  restore() {
    this.observer.disconnect();
    for (const [node, text] of this.originals) node.textContent = text;
    for (const [element, attributes] of this.attributes) {
      for (const [name, value] of attributes) {
        if (value === null) element.removeAttribute(name);
        else element.setAttribute(name, value);
      }
    }
    this.originals.clear();
    this.attributes.clear();
    this.images.clear();
    this.element.style.removeProperty("--mihi-portrait");
    this.enabled = false;
    this.updateButtons();
  }
}
