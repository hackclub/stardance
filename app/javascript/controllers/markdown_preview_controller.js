import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "input",
    "output",
    "preview",
    "writePanel",
    "writeTab",
    "previewTab",
    "helpDialog",
  ];
  static values = { url: String };

  #lastText = null;
  #debounceTimer = null;

  connect() {
    if (this.hasPreviewTarget && !this.hasOutputTarget) {
      this.#liveUpdate();
    }
  }

  update() {
    this.#liveUpdate();
  }

  showWrite() {
    if (this.hasWritePanelTarget) this.writePanelTarget.hidden = false;
    if (this.#outputEl) this.#outputEl.hidden = true;
    this.#syncTabs("write");
  }

  showPreview() {
    if (this.hasWritePanelTarget) this.writePanelTarget.hidden = true;
    if (this.#outputEl) this.#outputEl.hidden = false;
    this.#syncTabs("preview");
    this.#fetchPreview();
  }

  openHelp(event) {
    event.preventDefault();
    if (this.hasHelpDialogTarget) this.helpDialogTarget.showModal();
  }

  closeHelp() {
    if (this.hasHelpDialogTarget) this.helpDialogTarget.close();
  }

  get #outputEl() {
    if (this.hasOutputTarget) return this.outputTarget;
    if (this.hasPreviewTarget) return this.previewTarget;
    return null;
  }

  #syncTabs(active) {
    if (this.hasWriteTabTarget) {
      this.writeTabTarget.setAttribute(
        "aria-selected",
        String(active === "write"),
      );
    }
    if (this.hasPreviewTabTarget) {
      this.previewTabTarget.setAttribute(
        "aria-selected",
        String(active === "preview"),
      );
    }
  }

  #liveUpdate() {
    const el = this.#outputEl;
    if (!el || !this.hasInputTarget) return;

    const markdown = this.inputTarget.value || "";
    if (markdown.trim() === "") {
      el.innerHTML =
        '<span class="markdown-preview__empty">Preview will appear here...</span>';
      return;
    }

    clearTimeout(this.#debounceTimer);
    this.#debounceTimer = setTimeout(() => {
      this.#renderInto(el, markdown);
    }, 300);
  }

  async #fetchPreview() {
    const el = this.#outputEl;
    if (!el || !this.hasInputTarget) return;

    const text = this.inputTarget.value || "";
    if (text.trim() === "") {
      el.innerHTML = '<p class="md-preview__empty">Nothing to preview</p>';
      this.#lastText = null;
      return;
    }
    if (text === this.#lastText) return;

    el.innerHTML = '<p class="md-preview__loading">Loading preview…</p>';
    const html = await this.#renderInto(el, text);
    if (html !== null) this.#lastText = text;
  }

  async #renderInto(el, markdown) {
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            ?.content,
        },
        body: new URLSearchParams({ markdown }),
      });

      if (response.ok) {
        const html = await response.text();
        el.innerHTML =
          html || '<p class="md-preview__empty">Nothing to preview</p>';
        return html;
      }
    } catch {
      // silent — preview is non-critical
    }

    el.innerHTML = '<p class="md-preview__empty">Preview unavailable</p>';
    return null;
  }
}
