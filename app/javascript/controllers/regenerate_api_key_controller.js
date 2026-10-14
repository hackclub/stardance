import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

// The trigger button lives inside the sidebar, which is `data-turbo-permanent`
// so Turbo never re-renders it across navigations. A plain <form> there would
// keep whatever authenticity_token was baked in on this tab's very first page
// load, forever — a perfectly valid session could still get CSRF-rejected.
// Reading the token from the page's <meta> tag at submit time instead stays
// correct no matter how long this button has been sitting in the DOM.
export default class extends Controller {
  static values = { url: String };

  async regenerate(event) {
    event.preventDefault();

    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
          ?.content,
      },
    });

    // Grab this before rendering the stream below replaces our button (and
    // detaches it from the tree, breaking `closest` lookups afterward).
    const dialog = this.element.closest("dialog[open]");

    const html = await response.text();
    if (response.headers.get("Content-Type")?.includes("turbo-stream")) {
      Turbo.renderStreamMessage(html);
      dialog?.close();
    } else {
      Turbo.visit(response.url);
    }
  }
}
