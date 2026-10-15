import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { url: String };
  static targets = ["status"];

  async copy(event) {
    event.preventDefault();
    try {
      if (
        !navigator.clipboard ||
        !window.ClipboardItem ||
        !window.isSecureContext
      ) {
        throw new Error("clipboard unsupported");
      }
      // Pass the promise straight to ClipboardItem so Safari keeps the
      // user-gesture context while the PNG downloads.
      const item = new ClipboardItem({
        "image/png": fetch(this.urlValue).then((response) => {
          if (!response.ok) throw new Error("image fetch failed");
          return response.blob();
        }),
      });
      await navigator.clipboard.write([item]);
      this.#status("Copied! Paste it anywhere.");
    } catch {
      this.#status("Couldn't copy on this browser — use Download PNG instead.");
    }
  }

  #status(message) {
    if (!this.hasStatusTarget) return;
    this.statusTarget.textContent = message;
    clearTimeout(this.statusTimeout);
    this.statusTimeout = setTimeout(() => {
      this.statusTarget.textContent = "";
    }, 4000);
  }

  disconnect() {
    clearTimeout(this.statusTimeout);
  }
}
