import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["warning"];
  static values = {
    itemType: String,
    usOriginMessage: String,
    ukOriginMessage: String,
    unknownOriginMessage: String,
    thirdPartyMessage: String,
    customRegionMessage: String,
    sourceRegion: String,
  };

  static c = {
    US: ["US"],
    EU: [
      "AT",
      "BE",
      "BG",
      "HR",
      "CY",
      "CZ",
      "DK",
      "EE",
      "FI",
      "FR",
      "DE",
      "GR",
      "HU",
      "IE",
      "IT",
      "LV",
      "LT",
      "LU",
      "MT",
      "NL",
      "PL",
      "PT",
      "RO",
      "SK",
      "SI",
      "ES",
      "SE",
    ],
    UK: ["GB"],
    IN: ["IN"],
    CA: ["CA"],
    AU: ["AU", "NZ"],
    XX: [],
  };

  connect() {
    this.updateWarning(null);
  }

  addressChanged(event) {
    const country = event.detail?.country || null;
    this.updateWarning(country);
  }

  updateWarning(country) {
    if (!this.hasWarningTarget) return;

    const itemType = this.itemTypeValue;
    let shouldShow = false;
    let message = "";

    switch (itemType) {
      case "us_origin":
        shouldShow = country !== null && country !== "US";
        message = this.usOriginMessageValue;
        break;
      case "uk_origin":
        shouldShow = country !== null && country !== "UK";
        message = this.ukOriginMessageValue;
        break;
      case "unknown_origin":
        shouldShow = true;
        message = this.unknownOriginMessageValue;
        break;
      case "third_party":
        shouldShow = country !== null;
        message = this.thirdPartyMessageValue;
        break;
      case "custom_region":
        shouldShow =
          country !== null && !this.ccRegion(country, this.sourceRegionValue);
        message = this.customRegionMessageValue;
        break;
      default:
        shouldShow = false;
    }

    if (shouldShow && message) {
      this.warningTarget.textContent = message;
      this.warningTarget.style.display = "block";
    } else {
      this.warningTarget.style.display = "none";
    }
  }

  ccRegion(countryCode, regionCode) {
    if (!regionCode) return true;

    const countries = this.constructor.c[regionCode.toUpperCase()];
    if (!countries) return false;

    return countries.includes(countryCode.toUpperCase());
  }
}
