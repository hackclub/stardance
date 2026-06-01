import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "sortBtn",
    "items",
    "empty",
    "stardustMinInput",
    "stardustMaxInput",
    "stardustMinValue",
    "stardustMaxValue",
    "stardustTrackFill",
  ];
  static values = { userRegion: { type: String, default: "US" } };

  connect() {
    this.sortAscending = true;
    this.sortType = "Prices";
    this.categoryFilter = "All";
    this.stardustMin = this.stardustMinValue();
    this.stardustMax = this.stardustMaxValue();
    this.regionFilter = this.userRegionValue;
    this.accessFilter = "All";

    const searchInput = this.element.querySelector(
      '[data-action*="shop#search"]',
    );
    this.searchQuery = (searchInput?.value || "").toLowerCase();

    this.setupSortButton();
    this.updateStardustRange();
    this.applyFiltersAndSort();
  }

  setupSortButton() {
    const sortBtn = document.getElementById("sort-btn");
    if (sortBtn) {
      sortBtn.addEventListener("click", () => this.toggleSort());
    }
  }

  filter(event) {
    const select = event.target;
    const filterType = select.dataset.filterType;
    const value = select.value;

    if (filterType === "Category") {
      this.categoryFilter = value;
    } else if (filterType === "Sort by") {
      this.sortType = value;
    } else if (filterType === "Region") {
      this.regionFilter = value;
      this.saveRegion(value);
    } else if (filterType === "Access") {
      this.accessFilter = value;
    }

    this.applyFiltersAndSort();
  }

  stardustRangeChanged() {
    this.updateStardustRange();
    this.applyFiltersAndSort();
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
    const itemsContainer =
      document.querySelector(".shop-category__items") ||
      document.querySelector(".shop__items");
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

    const visibleCount = items.filter((i) => i.style.display !== "none").length;
    if (this.hasEmptyTarget) {
      this.emptyTarget.style.display = visibleCount === 0 ? "flex" : "none";
    }

    this.sortItems();
  }

  checkCategory(item) {
    if (this.categoryFilter === "All") return true;
    const itemCategories = (item.dataset.categories || "").split(",");
    return itemCategories.includes(this.categoryFilter);
  }

  checkPrice(item) {
    const price = this.extractPrice(item);
    return price >= this.stardustMin && price <= this.stardustMax;
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

  sortItems() {
    const itemsContainer =
      document.querySelector(".shop-category__items") ||
      document.querySelector(".shop__items");
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

  updateStardustRange() {
    if (!this.hasStardustMinInputTarget || !this.hasStardustMaxInputTarget) {
      return;
    }

    const min = this.stardustMinValue();
    const max = this.stardustMaxValue();

    if (min > max) {
      const activeInput = document.activeElement;
      if (activeInput === this.stardustMinInputTarget) {
        this.stardustMaxInputTarget.value = min;
      } else {
        this.stardustMinInputTarget.value = max;
      }
    }

    this.stardustMin = this.stardustMinValue();
    this.stardustMax = this.stardustMaxValue();

    if (this.hasStardustMinValueTarget) {
      this.stardustMinValueTarget.textContent = this.formatStardust(
        this.stardustMin,
      );
    }

    if (this.hasStardustMaxValueTarget) {
      this.stardustMaxValueTarget.textContent = this.formatStardust(
        this.stardustMax,
      );
    }

    this.updateStardustTrackFill();
  }

  updateStardustTrackFill() {
    if (
      !this.hasStardustTrackFillTarget ||
      !this.hasStardustMinInputTarget ||
      !this.hasStardustMaxInputTarget
    ) {
      return;
    }

    const sliderMin = parseFloat(this.stardustMinInputTarget.min) || 0;
    const sliderMax = parseFloat(this.stardustMaxInputTarget.max) || 10000;
    const sliderRange = sliderMax - sliderMin;
    const minPercent = ((this.stardustMin - sliderMin) / sliderRange) * 100;
    const maxPercent = ((this.stardustMax - sliderMin) / sliderRange) * 100;

    this.stardustTrackFillTarget.style.left = `${minPercent}%`;
    this.stardustTrackFillTarget.style.right = `${100 - maxPercent}%`;
  }

  stardustMinValue() {
    const input = this.hasStardustMinInputTarget
      ? this.stardustMinInputTarget
      : null;
    return this.parseStardustInput(input, 0);
  }

  stardustMaxValue() {
    const input = this.hasStardustMaxInputTarget
      ? this.stardustMaxInputTarget
      : null;
    return this.parseStardustInput(input, 10000);
  }

  parseStardustInput(input, fallback) {
    if (!input) return fallback;

    const value = parseInt(input.value, 10);
    return Number.isNaN(value) ? fallback : value;
  }

  formatStardust(value) {
    return new Intl.NumberFormat().format(value);
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
