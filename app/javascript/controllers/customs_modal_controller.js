import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dialog", "euNote"];
  static values = {
    itemType: String,
    sourceRegion: String,
    storageKey: String,
    euCountries: Array,
  };

  connect() {
    this.pendingSubmit = null;
    this.currentCountry = null;
  }

  addressChanged(event) {
    this.currentCountry = event.detail?.country || null;
  }

  interceptSubmit(event) {
    if (!this.shouldShowModal()) return;
    if (this.isDismissed()) return;

    event.preventDefault();
    this.pendingSubmit = event.target;
    this.updateEuNote();
    this.dialogTarget.showModal();
  }

  confirm() {
    this.storeDismissal();
    this.closeDialog();
    if (this.pendingSubmit) {
      this.pendingSubmit.requestSubmit();
      this.pendingSubmit = null;
    }
  }

  cancel() {
    this.closeDialog();
    this.pendingSubmit = null;
  }

  closeDialog() {
    if (typeof this.dialogTarget.close === "function") {
      this.dialogTarget.close();
    } else {
      this.dialogTarget.removeAttribute("open");
    }
  }

  updateEuNote() {
    if (!this.hasEuNoteTarget) return;
    const isEu =
      this.currentCountry &&
      this.euCountriesValue.includes(this.currentCountry.toUpperCase());
    this.euNoteTarget.style.display = isEu ? "block" : "none";
  }

  shouldShowModal() {
    const itemType = this.itemTypeValue;
    if (itemType === "none") return false;

    const country = this.currentCountry;
    if (!country) return false;

    switch (itemType) {
      case "us_origin":
        return country !== "US";
      case "uk_origin":
        return country !== "GB";
      case "unknown_origin":
        return true;
      case "custom_region":
        return !this.isInRegion(country, this.sourceRegionValue);
      default:
        return false;
    }
  }

  isInRegion(countryCode, regionCode) {
    if (!regionCode) return true;
    if (regionCode.toUpperCase() === "EU") {
      return this.euCountriesValue.includes(countryCode.toUpperCase());
    }
    return false;
  }

  isDismissed() {
    try {
      return localStorage.getItem(this.storageKeyValue) === "1";
    } catch {
      return false;
    }
  }

  storeDismissal() {
    try {
      localStorage.setItem(this.storageKeyValue, "1");
    } catch {
      // localStorage unavailable — fail open
    }
  }
}
