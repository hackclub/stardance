import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button"];
  static values = { reviewId: Number };

  async complete(event) {
    event.preventDefault();
    if (this.buttonTarget.disabled) return;

    if (
      !confirm(
        "Are you sure you want to complete this review? This will sync the review to Airtable and mark it as done.",
      )
    ) {
      return;
    }

    const buttonContents = [...this.buttonTarget.childNodes];
    const controls = [
      ...this.element.querySelectorAll(
        ".devlog-item:not(.devlog-item--frozen) input, .devlog-item:not(.devlog-item--frozen) textarea, .devlog-item:not(.devlog-item--frozen) button",
      ),
    ];
    const enabledControls = controls.filter((control) => !control.disabled);
    const active = document.activeElement;
    const selection =
      active instanceof HTMLTextAreaElement
        ? [
            active.selectionStart,
            active.selectionEnd,
            active.selectionDirection,
          ]
        : null;
    enabledControls.forEach((control) => (control.disabled = true));
    this.buttonTarget.disabled = true;
    this.buttonTarget.textContent = "Completing...";
    let redirecting = false;

    try {
      const pending = [];
      window.dispatchEvent(
        new CustomEvent("devlog-review:flush", { detail: { pending } }),
      );
      const saved = await Promise.all(pending);
      if (saved.some((success) => !success)) {
        this.showFlash(
          "Some devlog edits could not be saved. Review them and try completing again.",
          "error",
        );
        return;
      }
      const csrfToken = document.querySelector(
        'meta[name="csrf-token"]',
      )?.content;
      const response = await fetch(
        `/admin/certification/review/${this.reviewIdValue}/complete`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken,
          },
        },
      );

      const data = await response.json();

      if (response.ok) {
        redirecting = true;
        this.showFlash(
          data.message ||
            "Review completed successfully! Redirecting to review queue...",
          "success",
        );
        window.location.href =
          data.redirect_url || "/admin/certification/review";
      } else {
        const errorMessage =
          data.error || data.errors?.join(", ") || "Failed to complete review";
        this.showFlash(errorMessage, "error");
      }
    } catch (error) {
      console.error("Error completing review:", error);
      this.showFlash(
        "An unexpected error occurred. Please try again.",
        "error",
      );
    } finally {
      if (!redirecting) {
        enabledControls.forEach((control) => (control.disabled = false));
        this.buttonTarget.disabled = false;
        this.buttonTarget.replaceChildren(...buttonContents);
        if (
          active?.isConnected &&
          enabledControls.includes(active) &&
          document.activeElement === document.body
        ) {
          active.focus({ preventScroll: true });
          if (selection) active.setSelectionRange(...selection);
        }
      }
    }
  }

  showFlash(message, variant = "error") {
    let container = document.querySelector(".flash-container");
    if (!container) {
      container = document.createElement("div");
      container.className = "flash-container";
      document.body.appendChild(container);
    }

    const el = document.createElement("div");
    el.className = `alert alert-${variant}`;
    el.setAttribute("role", "alert");
    el.setAttribute("aria-live", "assertive");
    el.setAttribute("data-controller", "flash");
    el.setAttribute("data-flash-timeout-value", "5000");
    el.innerHTML = `
      <div class="alert__content">${message}</div>
      <button type="button" class="alert__close" aria-label="Close" data-action="click->flash#close">×</button>
    `;
    container.appendChild(el);
  }
}
