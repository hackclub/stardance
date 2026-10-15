import { Controller } from "@hotwired/stimulus";

const INTERACTIVE_SELECTOR =
  "a, button, summary, input, textarea, select, label, video, audio, dialog, [role='button']";

export default class extends Controller {
  static values = { url: String };

  navigate(event) {
    if (!this.shouldNavigate(event)) return;

    event.preventDefault();
    event.stopPropagation();

    if (this.opensInNewTab(event)) {
      window.open(this.urlValue, "_blank", "noopener");
      return;
    }

    const detail = { url: this.urlValue };
    const navEvent = this.dispatch("navigate", {
      detail,
      cancelable: true,
    });

    if (!navEvent.defaultPrevented) {
      window.location.href = this.urlValue;
    }
  }

  // Comment buttons open the post panel scrolled to its composer; where no
  // panel is listening, links follow their href and buttons navigate manually.
  navigateComments(event) {
    if (!this.urlValue) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey) return;

    const navEvent = this.dispatch("navigate", {
      detail: { url: this.urlValue, comments: true },
      cancelable: true,
    });

    if (navEvent.defaultPrevented) {
      event.preventDefault();
      event.stopPropagation();
    } else if (event.currentTarget.tagName !== "A") {
      window.location.href = `${this.urlValue}#comments`;
    }
  }

  shouldNavigate(event) {
    return (
      this.urlValue &&
      (event.button === 0 || event.button === 1) &&
      !event.target.closest(INTERACTIVE_SELECTOR) &&
      !this.hasSelectedText()
    );
  }

  opensInNewTab(event) {
    return (
      event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1
    );
  }

  hasSelectedText() {
    const selection = window.getSelection();
    if (!selection || selection.isCollapsed || !selection.toString().trim()) {
      return false;
    }

    return (
      this.element.contains(selection.anchorNode) ||
      this.element.contains(selection.focusNode)
    );
  }
}
