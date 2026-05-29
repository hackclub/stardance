import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "input",
    "preview",
    "dropdown",
    "submitButton",
    "summaryQtyDisplay",
    "summaryTotalDisplay",
    "accessoriesListContainer",
    "accessoriesListItems",
  ];

  static values = {
    addresses: Array,
    hasAddresses: Boolean,
    baseTicketCost: Number,
    userBalance: Number,
    blockedCountries: Array,
    stardustIconUrl: String,
  };

  stardustIconHtml() {
    return `<img src="${this.stardustIconUrlValue}" alt="Stardust" class="currency-icon">`;
  }

  connect() {
    if (this.hasSubmitButtonTarget) {
      this.initialGetButtonHTML = this.submitButtonTarget.innerHTML;
    }

    this.setupAccessoryRadioUndo();
    this.setupModifierRadioUndo();
    this.setupOrderSummary();
    this.setupBlockedCountryCheck();
  }

  setupBlockedCountryCheck() {
    this.banner = document.querySelector("[data-blocked-country-banner]");
    if (!this.banner) return;
    const a =
      this.addressesValue.find((x) => x.primary) || this.addressesValue[0];
    if (a) this.checkBlockedCountry(a.country);
  }

  addressChanged(e) {
    if (e.detail?.country) this.checkBlockedCountry(e.detail.country);
  }

  checkBlockedCountry(c) {
    if (!c) return;
    const blocked = this.blockedCountriesValue.includes(c.toUpperCase());
    this.banner.style.display = blocked ? "block" : "none";
    if (!this.hasSubmitButtonTarget) return;
    this.submitButtonTarget.disabled = blocked;
    this.submitButtonTarget.innerHTML = blocked
      ? "Not available in your country"
      : this.initialGetButtonHTML;
    if (!blocked) this.updateOrderSummary();
  }

  setupAccessoryRadioUndo() {
    const radios = this.element.querySelectorAll(
      ".shop-order__accessory-option-input",
    );
    radios.forEach((radio) => {
      radio.addEventListener("click", () => {
        if (radio.dataset.wasChecked === "true") {
          radio.checked = false;
          radio.dataset.wasChecked = "false";
          radio.dispatchEvent(new Event("change", { bubbles: true }));
        } else {
          this.element
            .querySelectorAll(`input[name="${radio.name}"]`)
            .forEach((r) => {
              r.dataset.wasChecked = "false";
            });
          radio.dataset.wasChecked = "true";
        }
      });
    });
  }

  setupModifierRadioUndo() {
    const radios = this.element.querySelectorAll(
      ".shop-order__modifier-option-input[type='radio']",
    );
    radios.forEach((radio) => {
      radio.addEventListener("click", () => {
        if (radio.dataset.wasChecked === "true") {
          radio.checked = false;
          radio.dataset.wasChecked = "false";
          radio.dispatchEvent(new Event("change", { bubbles: true }));
        } else {
          this.element
            .querySelectorAll(`input[name="${radio.name}"]`)
            .forEach((r) => {
              r.dataset.wasChecked = "false";
            });
          radio.dataset.wasChecked = "true";
        }
      });
    });
  }

  setupOrderSummary() {
    this.quantityInput =
      this.element.querySelector("#shop-order__quantity-input") || null;

    this.accessoryCheckboxes = this.element.querySelectorAll(
      ".shop-order__accessory-option-input[type='checkbox']",
    );
    this.accessoryRadios = this.element.querySelectorAll(
      ".shop-order__accessory-option-input[type='radio']",
    );
    this.modifierCheckboxes = this.element.querySelectorAll(
      ".shop-order__modifier-option-input[type='checkbox']",
    );
    this.modifierRadios = this.element.querySelectorAll(
      ".shop-order__modifier-option-input[type='radio']",
    );

    if (this.quantityInput) {
      this.quantityInput.addEventListener("input", () =>
        this.updateOrderSummary(),
      );
    }

    this.accessoryCheckboxes.forEach((checkbox) => {
      checkbox.addEventListener("change", () => this.updateOrderSummary());
    });

    this.accessoryRadios.forEach((radio) => {
      radio.addEventListener("change", () => this.updateOrderSummary());
    });

    this.modifierCheckboxes.forEach((checkbox) => {
      checkbox.addEventListener("change", () => this.updateOrderSummary());
    });

    this.modifierRadios.forEach((radio) => {
      radio.addEventListener("change", () => this.updateOrderSummary());
    });

    this.updateOrderSummary();
  }

  getSelectedAccessories() {
    const accessories = [];

    this.accessoryCheckboxes.forEach((checkbox) => {
      if (checkbox.checked) {
        const name = checkbox
          .closest("label")
          .querySelector(".shop-order__accessory-option-name").textContent;
        const price = parseFloat(checkbox.dataset.price) || 0;
        accessories.push({ name, price });
      }
    });

    this.accessoryRadios.forEach((radio) => {
      if (radio.checked) {
        const name = radio
          .closest("label")
          .querySelector(".shop-order__accessory-option-name").textContent;
        const price = parseFloat(radio.dataset.price) || 0;
        accessories.push({ name, price });
      }
    });

    return accessories;
  }

  getSelectedModifiers() {
    const modifiers = [];

    this.modifierCheckboxes.forEach((checkbox) => {
      if (checkbox.checked) {
        const name =
          checkbox.dataset.name ||
          checkbox
            .closest("label")
            .querySelector(".shop-order__accessory-option-name")?.textContent ||
          "";
        const price = parseFloat(checkbox.dataset.price) || 0;
        modifiers.push({ name, price });
      }
    });

    this.modifierRadios.forEach((radio) => {
      if (radio.checked) {
        const name =
          radio.dataset.name ||
          radio
            .closest("label")
            .querySelector(".shop-order__accessory-option-name")?.textContent ||
          "";
        const price = parseFloat(radio.dataset.price) || 0;
        modifiers.push({ name, price });
      }
    });

    return modifiers;
  }

  updateOrderSummary() {
    const qty =
      parseInt(this.quantityInput ? this.quantityInput.value : 1, 10) || 1;
    const accessories = this.getSelectedAccessories();
    const modifiers = this.getSelectedModifiers();
    const accTotal = accessories.reduce((sum, acc) => sum + acc.price, 0);
    const modTotal = modifiers.reduce((sum, mod) => sum + mod.price, 0);
    // Accessories are multiplied by quantity; modifiers are per-order (not per-unit)
    const total = this.baseTicketCostValue * qty + accTotal * qty + modTotal;

    if (
      this.hasAccessoriesListContainerTarget &&
      this.hasAccessoriesListItemsTarget
    ) {
      const allSelections = [
        ...accessories.map((a) => ({
          ...a,
          display: `${a.name} ${qty > 1 ? `(${qty}x)` : ""}`,
          cost: Math.round(a.price * qty),
        })),
        ...modifiers.map((m) => ({
          ...m,
          display: m.name,
          cost: Math.round(m.price),
        })),
      ];

      if (allSelections.length > 0) {
        this.accessoriesListContainerTarget.style.display = "block";
        this.accessoriesListItemsTarget.innerHTML = allSelections
          .map(
            (s) =>
              `<li>${s.display} <span>${s.cost > 0 ? `${this.stardustIconHtml()} ${s.cost}` : "Free"}</span></li>`,
          )
          .join("");
      } else {
        this.accessoriesListContainerTarget.style.display = "none";
        this.accessoriesListItemsTarget.innerHTML = "";
      }
    }

    if (this.hasSummaryQtyDisplayTarget) {
      this.summaryQtyDisplayTarget.textContent = `${qty}x`;
    }

    if (this.hasSummaryTotalDisplayTarget) {
      this.summaryTotalDisplayTarget.innerHTML = `${this.stardustIconHtml()} ${Math.round(total)}`;
    }

    if (this.hasSubmitButtonTarget) {
      const canAfford = this.userBalanceValue >= total;
      const shortfall = Math.max(0, total - this.userBalanceValue);

      if (canAfford && this.hasAddressesValue) {
        this.submitButtonTarget.disabled = false;
        this.submitButtonTarget.innerHTML = this.initialGetButtonHTML;
      } else if (!canAfford) {
        this.submitButtonTarget.disabled = true;
        this.submitButtonTarget.innerHTML = `You need ${this.stardustIconHtml()} ${shortfall.toFixed(0)} more Stardust!`;
      } else {
        this.submitButtonTarget.disabled = true;
        this.submitButtonTarget.innerHTML = this.initialGetButtonHTML;
      }
    }
  }
}
