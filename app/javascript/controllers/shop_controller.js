import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["sortBtn", "items"];
  static values = { userRegion: { type: String, default: "US" } };

  connect() {
    this.sortAscending = true;
    this.sortType = "Prices";
    this.categoryFilter = "All";
    this.priceRange = "none";
    this.regionFilter = this.userRegionValue;
    this.searchQuery = "";
    this.accessFilter = "All";

    this.setupSortButton();
    this.setupFilterListeners();
    this.applyFiltersAndSort();
  }

  setupSortButton() {
    const sortBtn = document.getElementById("sort-btn");
    if (sortBtn) {
      sortBtn.addEventListener("click", () => this.toggleSort());
    }
  }

  setupFilterListeners() {
    document.addEventListener("shop:filter", (event) => {
      const { filterType, value } = event.detail;

      if (filterType === "Category") {
        this.categoryFilter = value;
      } else if (filterType === "Price Range") {
        this.priceRange = value;
      } else if (filterType === "Sort by") {
        this.sortType = value;
      } else if (filterType === "Region") {
        this.regionFilter = value;
        this.saveRegion(value);
      } else if (filterType === "Access") {
        this.accessFilter = value;
      }

      this.applyFiltersAndSort();
    });
  }

  toggleSort() {
    this.sortAscending = !this.sortAscending;
    const sortBtn = document.getElementById("sort-btn");
    if (sortBtn) {
      sortBtn.classList.toggle("descending", !this.sortAscending);
    }
    this.applyFiltersAndSort();
  }

  applyFiltersAndSort() {
    const itemsContainer = document.querySelector(".shop__items");
    if (!itemsContainer) return;

    const items = Array.from(
      itemsContainer.querySelectorAll(".shop-item-card"),
    );

    items.forEach((item) => {
      const passesCategory = this.checkCategory(item);
      const passesPrice = this.checkPrice(item);
      const passesSearch = this.checkSearch(item);
      const passesRegion = this.checkRegion(item);
      const passesAccess = this.checkAccess(item);

      item.style.display =
        passesCategory &&
        passesPrice &&
        passesSearch &&
        passesRegion &&
        passesAccess
          ? "flex"
          : "none";
    });

    this.sortItems();
  }

  checkCategory(item) {
    if (this.categoryFilter === "All") return true;
    const itemCategories = (item.dataset.categories || "").split(",");
    return itemCategories.includes(this.categoryFilter);
  }

  checkPrice(item) {
    const [min, max] = this.getPriceRange(this.priceRange);
    const price = this.extractPrice(item);
    return price >= min && price <= max;
  }

  checkSearch(item) {
    if (!this.searchQuery) return true;
    const title =
      item
        .querySelector(".shop-item-card__title")
        ?.textContent?.toLowerCase() || "";
    return title.includes(this.searchQuery);
  }

  checkRegion(item) {
    const itemRegions = (item.dataset.regions || "").split(",");
    return itemRegions.includes(this.regionFilter);
  }

  checkAccess(item) {
    if (this.accessFilter === "All") return true;
    const isLocked = item.dataset.achievementLocked === "true";
    if (this.accessFilter === "Available") return !isLocked;
    if (this.accessFilter === "Locked") return isLocked;
    return true;
  }

  getPriceRange(range) {
    if (range === "none") return [0, Infinity];
    if (range === "0-100") return [0, 100];
    if (range === "100-500") return [100, 500];
    if (range === "500-1000") return [500, 1000];
    if (range === "1000+") return [1000, Infinity];
    return [0, Infinity];
  }

  sortItems() {
    const itemsContainer = document.querySelector(".shop__items");
    if (!itemsContainer) return;

    const items = Array.from(
      itemsContainer.querySelectorAll(".shop-item-card"),
    );

    if (this.sortType === "Prices") {
      items.sort((a, b) => {
        const priceA = this.extractPrice(a);
        const priceB = this.extractPrice(b);
        return this.sortAscending ? priceA - priceB : priceB - priceA;
      });
    } else if (this.sortType === "Alphabetical") {
      items.sort((a, b) => {
        const nameA =
          a.querySelector(".shop-item-card__title")?.textContent || "";
        const nameB =
          b.querySelector(".shop-item-card__title")?.textContent || "";
        return this.sortAscending
          ? nameA.localeCompare(nameB)
          : nameB.localeCompare(nameA);
      });
    }

    items.forEach((item) => itemsContainer.appendChild(item));
  }

  extractPrice(element) {
    // Use the data attribute which has the correct sale price
    const dataPrice = element.dataset.shopWishlistItemPriceValue;
    if (dataPrice) return parseFloat(dataPrice) || 0;

    // Fallback to text content - get the last number (sale price if present)
    const priceText = element.querySelector(
      ".shop-item-card__price",
    )?.textContent;
    if (!priceText) return 0;
    const numbers = priceText.match(/\d+/g);
    return numbers ? parseFloat(numbers[numbers.length - 1]) : 0;
  }

  search(event) {
    this.searchQuery = event.target.value.toLowerCase();
    this.applyFiltersAndSort();
  }

  saveRegion(region) {
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]',
    )?.content;
    const formData = new FormData();
    formData.append("region", region);

    fetch("/shop/region", {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        Accept: "text/vnd.turbo-stream.html",
      },
      body: formData,
    })
      .then((response) => response.text())
      .then((html) => {
        Turbo.renderStreamMessage(html);
        // Wait for Turbo to finish updating the DOM
        requestAnimationFrame(() => {
          this.applyFiltersAndSort();
        });
      });
  }
}
