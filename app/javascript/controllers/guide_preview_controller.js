import { Controller } from "@hotwired/stimulus";

// Debounced live preview for the manage-side guide textarea. The endpoint
// returns 413 above 100KB; that's treated as a no-op (keep prior preview).
export default class extends Controller {
  static targets = ["input", "preview"];
  static values = { url: String };

  connect() {
    this.update();
  }

  update() {
    const markdown = this.inputTarget.value || "";
    if (markdown.trim() === "") {
      this.previewTarget.innerHTML =
        '<span class="guide-preview__empty">Preview will appear here…</span>';
      return;
    }

    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.fetchPreview(markdown);
    }, 350);
  }

  async fetchPreview(markdown) {
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
        this.previewTarget.innerHTML =
          html ||
          '<span class="guide-preview__empty">Preview will appear here…</span>';
      }
    } catch (_e) {}
  }
}
