import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static values = { itemId: String, wishlisted: Boolean };

  toggle(event) {
    event.preventDefault();
    event.stopPropagation();

    const wasWishlisted = this.wishlistedValue;
    this.wishlistedValue = !wasWishlisted;

    const method = wasWishlisted ? "DELETE" : "POST";
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]',
    )?.content;

    fetch(`/shop/wishlists/${this.itemIdValue}`, {
      method,
      headers: {
        "X-CSRF-Token": csrfToken,
        Accept: "text/vnd.turbo-stream.html",
      },
    })
      .then(async (r) => {
        if (r.ok) {
          const html = await r.text();
          Turbo.renderStreamMessage(html);
        } else {
          this.wishlistedValue = wasWishlisted;
        }
      })
      .catch(() => {
        // Offline or the request never landed: put the star back as it was.
        this.wishlistedValue = wasWishlisted;
      });
  }

  wishlistedValueChanged() {
    this.element.classList.toggle(
      "shop-item-card--wishlisted",
      this.wishlistedValue,
    );
  }
}
