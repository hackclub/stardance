import { Controller } from "@hotwired/stimulus";

// Advisory tools only: neither action submits or changes a review decision.
export default class extends Controller {
  static targets = ["draft", "fallback", "status", "justification", "insert"];
  static values = { guidelines: String };

  async copy() {
    try {
      await navigator.clipboard.writeText(this.draftTarget.value);
      this.statusTarget.textContent =
        "Copied. Verify the findings before sending.";
    } catch {
      this.fallbackTarget.hidden = false;
      this.draftTarget.focus();
      this.draftTarget.select();
      this.statusTarget.textContent =
        "Clipboard unavailable. Select and copy the draft below.";
    }
  }

  connect() {
    if (!this.hasJustificationTarget) return;
    this.syncDisabled();
    this.observer = new MutationObserver(() => this.syncDisabled());
    this.observer.observe(this.element, {
      attributes: true,
      subtree: true,
      attributeFilter: ["disabled", "readonly"],
    });
  }

  disconnect() {
    this.observer?.disconnect();
  }

  syncDisabled() {
    const disabled =
      this.justificationTarget.readOnly ||
      this.justificationTarget.matches(":disabled");
    if (this.insertTarget.disabled !== disabled) {
      this.insertTarget.disabled = disabled;
    }
  }

  preserveSelection(event) {
    if (event.button === 0) event.preventDefault();
  }

  insert() {
    const field = this.justificationTarget;
    if (field.readOnly || field.matches(":disabled")) return;

    const text = this.guidelinesValue;
    const start = field.selectionStart;
    const end = field.selectionEnd;
    if (
      field.maxLength >= 0 &&
      field.value.length - (end - start) + text.length > field.maxLength
    ) {
      this.statusTarget.textContent =
        "Not enough space for the full sentence. Shorten the justification or select text to replace.";
      field.focus();
      return;
    }

    if (
      !field.dispatchEvent(
        new InputEvent("beforeinput", {
          bubbles: true,
          cancelable: true,
          inputType: "insertText",
          data: text,
        }),
      )
    ) {
      this.statusTarget.textContent =
        "Insertion was blocked by the page. You can paste the guidelines manually.";
      return;
    }

    field.setRangeText(text, start, end, "end");
    field.focus();
    field.dispatchEvent(
      new InputEvent("input", {
        bubbles: true,
        inputType: "insertText",
        data: text,
      }),
    );
    field.dispatchEvent(new Event("change", { bubbles: true }));
    this.statusTarget.textContent =
      "Guidelines inserted. Nothing was submitted.";
  }
}
