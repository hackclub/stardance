import { Controller } from "@hotwired/stimulus";

// Converts a persisted shop item's type. Deliberately avoids a nested <form>
// (invalid HTML when this widget sits inside the main edit form, which
// corrupts the parser's tree and silently drops later fields from
// submission) by sending the PATCH itself.
export default class extends Controller {
  static targets = ["select", "button"];
  static values = { url: String };

  async convert() {
    const type = this.selectTarget.value;
    if (!type) return;

    this.buttonTarget.disabled = true;

    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]',
    )?.content;

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ shop_item: { type } }),
      });

      if (response.ok) {
        window.location.reload();
      } else {
        this.buttonTarget.disabled = false;
      }
    } catch {
      this.buttonTarget.disabled = false;
    }
  }
}
