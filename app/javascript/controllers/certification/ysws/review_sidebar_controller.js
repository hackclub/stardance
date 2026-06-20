import { Controller } from "@hotwired/stimulus";

// Transforms the review detail sidebar from sticky to a slide-out popup when
// the first devlog becomes visible. Returns to normal when scrolling back up.
//
// Targets:
//   - sidebar: The right sidebar element to transform
//   - trigger: The element that triggers the transformation (first devlog)
//   - toggle: The button that opens/closes the popup
//
// CSS Classes:
//   - is-popup-mode: Added to sidebar when first devlog is visible
//   - is-open: Added to sidebar when popup is manually opened

export default class extends Controller {
  static targets = ["sidebar", "trigger", "toggle", "actionsCard"];

  connect() {
    //console.log("Review sidebar controller connected!");
    if (typeof IntersectionObserver === "undefined") return;

    // Track popup open state
    this.isOpen = false;
    this.popupModeActivated = false;

    // Observe the trigger element (first devlog)
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && !this.popupModeActivated) {
            // First devlog is visible - transform to popup mode
            //console.log("First devlog visible - activating popup mode");
            this.popupModeActivated = true;
            this.sidebarTarget.classList.add("is-popup-mode");
            this.toggleTarget.classList.add("is-visible");
            if (this.hasActionsCardTarget) {
              this.actionsCardTarget.classList.add("is-visible");
            }
          }
        });
      },
      {
        // Only trigger when first devlog is well into the viewport
        // Negative top margin means element must scroll this far up before triggering
        threshold: 0.1,
        rootMargin: "-300px 0px 0px 0px",
      },
    );

    this.observer.observe(this.triggerTarget);

    // Listen for scroll to detect when user scrolls back to top
    this.scrollHandler = () => {
      // If scrolled near the top (within 200px), exit popup mode
      if (window.scrollY < 200 && this.popupModeActivated) {
        //console.log("Scrolled to top - returning to normal mode");
        this.popupModeActivated = false;
        this.sidebarTarget.classList.remove("is-popup-mode");
        this.sidebarTarget.classList.remove("is-open");
        this.toggleTarget.classList.remove("is-visible");
        this.isOpen = false;
        if (this.hasActionsCardTarget) {
          this.actionsCardTarget.classList.remove("is-visible");
        }
      }
    };

    window.addEventListener("scroll", this.scrollHandler, { passive: true });
  }

  disconnect() {
    this.observer?.disconnect();
    if (this.scrollHandler) {
      window.removeEventListener("scroll", this.scrollHandler);
    }
  }

  // Toggle the popup open/closed
  togglePopup() {
    this.isOpen = !this.isOpen;
    this.sidebarTarget.classList.toggle("is-open", this.isOpen);
  }

  // Explicitly close the popup (for click-outside behavior if needed)
  closePopup() {
    this.isOpen = false;
    this.sidebarTarget.classList.remove("is-open");
  }
}
