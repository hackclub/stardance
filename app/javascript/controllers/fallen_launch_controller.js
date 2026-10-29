import { Controller } from "@hotwired/stimulus";

// Clicking the Fallen card plays a full screen send-off before Fallen opens in
// this tab: a gold wash and then Fallen's night sky burst out from the click,
// Fallen's logo rises in the middle, and it all fades to dark (see
// .fallen-takeover). The overlay is appended to <body> because the rail would
// otherwise trap a fixed element inside it. Modified clicks and reduced motion
// go straight to the tracked link.

const OPEN_AFTER_MS = 1950; // once it has faded to dark

export default class extends Controller {
  static targets = ["takeover"];
  static values = { url: String };

  connect() {
    // Coming back with the browser's back button can restore this page as it
    // was left, overlay and all, so clear it when the page is shown again.
    this.onPageShow = (event) => {
      if (event.persisted) this.reset();
    };
    window.addEventListener("pageshow", this.onPageShow);
  }

  disconnect() {
    window.removeEventListener("pageshow", this.onPageShow);
    this.reset();
  }

  launch(event) {
    if (
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey ||
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      return;
    }
    event.preventDefault();
    if (this.overlay) return; // already on its way

    // Count now, even if the visitor leaves during the send-off. The final
    // navigation skips this endpoint so the click is only recorded once.
    fetch(event.currentTarget.href, {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      cache: "no-store",
      keepalive: true,
    }).catch(() => {
      // Don't retry: the server may have counted a request whose response failed.
    });

    this.overlay =
      this.takeoverTarget.content.firstElementChild.cloneNode(true);
    const [x, y] = sweepOrigin(event);
    this.overlay.style.setProperty("--x", `${x}px`);
    this.overlay.style.setProperty("--y", `${y}px`);
    document.body.append(this.overlay);

    this.timer = setTimeout(
      () => window.location.assign(this.urlValue),
      OPEN_AFTER_MS,
    );
  }

  reset() {
    clearTimeout(this.timer);
    this.overlay?.remove();
    this.overlay = null;
  }
}

// Where the click landed, or the card's middle for a keyboard "click".
function sweepOrigin(event) {
  if (event.detail > 0) return [event.clientX, event.clientY];
  const rect = event.currentTarget.getBoundingClientRect();
  return [rect.left + rect.width / 2, rect.top + rect.height / 2];
}
