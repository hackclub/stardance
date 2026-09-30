import { Controller } from "@hotwired/stimulus";

// Publishes a fixed top banner's height as --top-banner-height so the page,
// sidebar and sticky headers can sit below it. Cleared when the banner leaves.
export default class extends Controller {
  connect() {
    this.observer = new ResizeObserver(() => this.publish());
    this.observer.observe(this.element);
    this.publish();
  }

  disconnect() {
    this.observer?.disconnect();
    document.documentElement.style.removeProperty("--top-banner-height");
  }

  publish() {
    document.documentElement.style.setProperty(
      "--top-banner-height",
      `${this.element.offsetHeight}px`,
    );
  }
}
