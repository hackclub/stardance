import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static values = { itemId: String, wishlisted: Boolean };

  toggle(event) {
    event.preventDefault();
    event.stopPropagation();

    const wasWishlisted = this.wishlistedValue;
    this.wishlistedValue = !wasWishlisted;
    if (!wasWishlisted) this.pop(event.currentTarget);

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
    }).then(async (r) => {
      if (r.ok) {
        const html = await r.text();
        Turbo.renderStreamMessage(html);
      } else {
        this.wishlistedValue = wasWishlisted;
      }
    });
  }

  // A little bounce when an item is starred. Skipped for reduced motion.
  pop(star) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    star.animate(
      [
        { transform: "scale(1) rotate(0deg)" },
        { transform: "scale(1.45) rotate(-18deg)", offset: 0.35 },
        { transform: "scale(0.9) rotate(8deg)", offset: 0.7 },
        { transform: "scale(1) rotate(0deg)" },
      ],
      { duration: 450, easing: "ease-out" },
    );
  }

  wishlistedValueChanged() {
    this.element.classList.toggle(
      "shop-item-card--wishlisted",
      this.wishlistedValue,
    );
  }
}
