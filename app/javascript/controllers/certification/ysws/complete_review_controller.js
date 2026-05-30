import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button"];
  static values = { reviewId: Number };

  async complete(event) {
    event.preventDefault();

    // Confirm with the reviewer
    if (
      !confirm(
        "Are you sure you want to complete this review? This will sync the review to Airtable and mark it as done.",
      )
    ) {
      return;
    }

    // Disable the button while processing
    this.buttonTarget.disabled = true;
    this.buttonTarget.textContent = "Completing...";

    try {
      const csrfToken = document.querySelector(
        'meta[name="csrf-token"]',
      ).content;
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
        // Show success message
        alert(
          data.message ||
            "Review completed successfully! Redirecting to review queue...",
        );

        // Redirect to the review queue
        if (data.redirect_url) {
          window.location.href = data.redirect_url;
        } else {
          window.location.href = "/admin/certification/review";
        }
      } else {
        const errorMessage =
          data.error || data.errors?.join(", ") || "Failed to complete review";
        alert(`Error: ${errorMessage}`);
        this.buttonTarget.disabled = false;
        this.buttonTarget.textContent = "Complete Review";
      }
    } catch (error) {
      console.error("Error completing review:", error);
      alert("An unexpected error occurred. Please try again.");
      this.buttonTarget.disabled = false;
      this.buttonTarget.textContent = "Complete Review";
    }
  }
}
