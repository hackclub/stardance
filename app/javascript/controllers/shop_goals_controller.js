import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["container", "items", "emptyState"];
  static values = { balance: Number };

  static STORAGE_KEY = "shop_wishlist";

  connect() {
    this.render();
    document.addEventListener("shop-wishlist:updated", () => this.render());
  }

  disconnect() {
    document.removeEventListener("shop-wishlist:updated", () => this.render());
  }

  getWishlist() {
    try {
      const data = localStorage.getItem(this.constructor.STORAGE_KEY);
      return data ? JSON.parse(data) : {};
    } catch {
      return {};
    }
  }

  render() {
    const wishlist = this.getWishlist();
    const items = Object.values(wishlist);

    if (items.length === 0) {
      this.containerTarget.style.display = "none";
      return;
    }

    this.containerTarget.style.display = "block";
    this.itemsTarget.innerHTML = items
      .map((item) => this.renderItem(item))
      .join("");
  }

  renderItem(item) {
    const balance = this.balanceValue;
    const progress = Math.min((balance / item.price) * 100, 100);
    const remaining = Math.round(Math.max(item.price - balance, 0));
    const canAfford = balance >= item.price;

    return `
      <div class="shop-goals__item" data-item-id="${item.id}">
        <button class="shop-goals__remove" data-action="click->shop-goals#remove" data-item-id="${item.id}" aria-label="Remove from goals">×</button>
        <a href="/shop/items/${item.id}" class="shop-goals__link">
          <img src="${item.image}" alt="${item.name}" class="shop-goals__image" />
          <div class="shop-goals__info">
            <span class="shop-goals__name">${item.name}</span>
            <div class="shop-goals__progress-container">
              <div class="shop-goals__progress-bar">
                <div class="shop-goals__progress-fill ${canAfford ? "shop-goals__progress-fill--complete" : ""}" style="width: ${progress}%"></div>
              </div>
              <span class="shop-goals__progress-text">
                ${canAfford ? "✓ Ready to order!" : `🍪${remaining.toLocaleString()} more needed`}
              </span>
            </div>
          </div>
        </a>
      </div>
    `;
  }

  remove(event) {
    event.preventDefault();
    event.stopPropagation();

    const itemId = event.currentTarget.dataset.itemId;
    const wishlist = this.getWishlist();
    delete wishlist[itemId];
    localStorage.setItem(
      this.constructor.STORAGE_KEY,
      JSON.stringify(wishlist),
    );

    const starButton = document.querySelector(
      `[data-shop-wishlist-item-id-value="${itemId}"] .shop-item-card__star`,
    );
    if (starButton) {
      starButton.classList.remove("shop-item-card__star--active");
      starButton.setAttribute("aria-pressed", "false");
    }

    this.render();
  }
}
