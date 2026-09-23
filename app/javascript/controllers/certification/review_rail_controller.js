import { Controller } from "@hotwired/stimulus";

// The T2 evidence rail: collapsible devlogs and one shared photo lightbox.
export default class extends Controller {
  static targets = ["lightbox", "lightboxImage"];

  toggleDevlog(event) {
    const devlog = event.currentTarget.closest(".review-cockpit__devlog");
    const content = devlog?.querySelector(".review-cockpit__devlog-content");
    if (!content) return;

    const collapsed = devlog.classList.toggle(
      "review-cockpit__devlog--collapsed",
    );
    event.currentTarget.textContent = collapsed ? "Expand" : "Collapse";
  }

  // Esc closes a <dialog> without closeImage, so drop the source on its close event.
  lightboxTargetConnected(dialog) {
    dialog.addEventListener("close", () => {
      this.lightboxImageTarget.src = "";
    });
  }

  openImage(event) {
    const src = event.currentTarget.dataset.fullSrc;
    if (!src || !this.hasLightboxTarget) return;

    this.lightboxImageTarget.src = src;
    this.lightboxTarget.showModal();
  }

  closeImage() {
    if (this.hasLightboxTarget) this.lightboxTarget.close();
  }
}
