import { Controller } from "@hotwired/stimulus";

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
        Accept: "application/json",
      },
    }).then((r) => {
      if (!r.ok) this.wishlistedValue = wasWishlisted;
    });
  }

  wishlistedValueChanged() {
    this.element.classList.toggle(
      "shop-item-card--wishlisted",
      this.wishlistedValue,
    );
  }
}
