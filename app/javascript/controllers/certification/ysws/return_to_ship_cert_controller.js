import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["modal", "textarea", "submitButton"];
  static values = { reviewId: Number };

  connect() {
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this);
  }

  open(event) {
    event.preventDefault();
    this.modalTarget.classList.add("is-open");
    this.textareaTarget.value = "";
    this.textareaTarget.focus();

    setTimeout(() => {
      document.addEventListener("click", this.closeOnOutsideClick);
    }, 0);
  }

  close(event) {
    if (event) event.preventDefault();
    this.modalTarget.classList.remove("is-open");
    document.removeEventListener("click", this.closeOnOutsideClick);
    this.submitButtonTarget.disabled = false;
    this.submitButtonTarget.textContent = "Return to Ship Certs";
  }

  closeOnOutsideClick(event) {
    if (event.target === this.modalTarget) this.close();
  }

  stopPropagation(event) {
    event.stopPropagation();
  }

  async submit(event) {
    event.preventDefault();
    const recertReason = this.textareaTarget.value.trim();

    if (!recertReason) {
      alert("Please provide a reason for returning this project.");
      return;
    }

    this.submitButtonTarget.disabled = true;
    this.submitButtonTarget.textContent = "Submitting...";

    try {
      const csrfMeta = document.querySelector('meta[name="csrf-token"]');
      const headers = { "Content-Type": "application/json" };
      if (csrfMeta) headers["X-CSRF-Token"] = csrfMeta.content;
      const response = await fetch(
        `/admin/certification/review/${this.reviewIdValue}/return_to_ship_cert`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({ recert_reason: recertReason }),
        },
      );

      const data = await response.json();

      if (response.ok) {
        alert(data.message || "Project returned to ship certification queue.");
        window.location.href =
          data.redirect_url || "/admin/certification/review";
      } else {
        alert(`Error: ${data.error || "Failed to return to ship certs"}`);
        this.submitButtonTarget.disabled = false;
        this.submitButtonTarget.textContent = "Return to Ship Certs";
      }
    } catch (error) {
      console.error("Error returning to ship certs:", error);
      alert("An unexpected error occurred. Please try again.");
      this.submitButtonTarget.disabled = false;
      this.submitButtonTarget.textContent = "Return to Ship Certs";
    }
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick);
  }
}
