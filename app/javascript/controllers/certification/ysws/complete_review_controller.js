import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button"];
  static values = { reviewId: Number };

  async complete(event) {
    event.preventDefault();

    if (
      !confirm(
        "Are you sure you want to complete this review? This will sync the review to Airtable and mark it as done.",
      )
    ) {
      return;
    }

    this.buttonTarget.disabled = true;
    this.buttonTarget.textContent = "Completing...";

    try {
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
        this.buttonTarget.disabled = false;
        this.buttonTarget.textContent = "Complete Review";
      }
    } catch (error) {
      console.error("Error completing review:", error);
      this.showFlash(
        "An unexpected error occurred. Please try again.",
        "error",
      );
      this.buttonTarget.disabled = false;
      this.buttonTarget.textContent = "Complete Review";
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
