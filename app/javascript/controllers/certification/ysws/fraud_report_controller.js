import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["modal", "textarea", "submitButton"];
  static values = { reviewId: Number };

  connect() {
    // Bind the close method to this instance so it works with event listeners
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this);
  }

  open(event) {
    event.preventDefault();
    this.modalTarget.classList.add("is-open");
    this.textareaTarget.value = ""; // Clear previous text
    this.textareaTarget.focus();

    // Add event listener for clicking outside
    setTimeout(() => {
      document.addEventListener("click", this.closeOnOutsideClick);
    }, 0);
  }

  close(event) {
    if (event) {
      event.preventDefault();
    }
    this.modalTarget.classList.remove("is-open");
    document.removeEventListener("click", this.closeOnOutsideClick);

    // Reset button state
    this.submitButtonTarget.disabled = false;
    this.submitButtonTarget.textContent = "Submit Report";
  }

  closeOnOutsideClick(event) {
    // Close if clicking outside the modal content
    if (event.target === this.modalTarget) {
      this.close();
    }
  }

  stopPropagation(event) {
    // Prevent clicks inside modal from bubbling up
    event.stopPropagation();
  }

  async submit(event) {
    event.preventDefault();
    const details = this.textareaTarget.value.trim();

    if (details.length < 20) {
      alert("Please provide at least 20 characters describing the issue.");
      return;
    }

    // Disable the submit button while processing
    this.submitButtonTarget.disabled = true;
    this.submitButtonTarget.textContent = "Submitting...";

    try {
      const csrfToken = document.querySelector(
        'meta[name="csrf-token"]',
      ).content;
      const response = await fetch(
        `/admin/certification/review/${this.reviewIdValue}/report_fraud`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken,
          },
          body: JSON.stringify({ details }),
        },
      );

      const data = await response.json();

      if (response.ok) {
        alert(
          "Report submitted successfully! The fraud squad has been notified.",
        );
        this.close();
      } else {
        const errorMessage = data.errors
          ? data.errors.join(", ")
          : "Failed to submit report";
        alert(`Error: ${errorMessage}`);
        this.submitButtonTarget.disabled = false;
        this.submitButtonTarget.textContent = "Submit Report";
      }
    } catch (error) {
      console.error("Error submitting fraud report:", error);
      alert("An unexpected error occurred. Please try again.");
      this.submitButtonTarget.disabled = false;
      this.submitButtonTarget.textContent = "Submit Report";
    }
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick);
  }
}
