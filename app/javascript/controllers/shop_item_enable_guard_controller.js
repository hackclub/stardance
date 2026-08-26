import { Controller } from "@hotwired/stimulus";

// Guards the "Enabled" checkbox on the new shop item form: non-Amber admins
// see a heads-up alert and must hold the override button for a few seconds
// before they can submit an item that starts enabled. Warehouse items have
// no override at all — they can only be enabled by Amber.
export default class extends Controller {
  static targets = [
    "enabledCheckbox",
    "alert",
    "primaryButton",
    "overrideButton",
  ];
  static values = {
    warehouse: Boolean,
    holdSeconds: { type: Number, default: 3 },
  };

  connect() {
    this.holdTimer = null;

    if (this.warehouseValue && this.hasEnabledCheckboxTarget) {
      this.enabledCheckboxTarget.checked = false;
      this.enabledCheckboxTarget.disabled = true;
    }

    this.refresh();
  }

  disconnect() {
    this.clearHoldTimer();
  }

  refresh() {
    const isEnabled =
      this.hasEnabledCheckboxTarget && this.enabledCheckboxTarget.checked;

    if (this.hasAlertTarget) this.alertTarget.hidden = !isEnabled;

    if (this.warehouseValue) return;

    if (!isEnabled) {
      this.setPrimaryDisabled(false);
      this.resetOverride();
      return;
    }

    this.setPrimaryDisabled(true);
    this.resetOverride();
  }

  setPrimaryDisabled(disabled) {
    if (this.hasPrimaryButtonTarget)
      this.primaryButtonTarget.disabled = disabled;
  }

  // The override button is intentionally never given the native `disabled`
  // attribute: disabled elements don't fire mouseenter/mouseleave/click in
  // browsers, which would make the hover-to-confirm timer unreachable.
  // "Armed" state is tracked via aria-disabled + a flag instead.
  resetOverride() {
    this.clearHoldTimer();
    this.overrideArmed = false;
    if (this.hasOverrideButtonTarget) {
      this.overrideButtonTarget.setAttribute("aria-disabled", "true");
      this.overrideButtonTarget.textContent = "Hold to confirm…";
    }
  }

  startHold() {
    if (!this.hasOverrideButtonTarget || this.overrideArmed) return;

    this.clearHoldTimer();
    this.holdTimer = window.setTimeout(() => {
      this.overrideArmed = true;
      this.overrideButtonTarget.setAttribute("aria-disabled", "false");
      this.overrideButtonTarget.textContent = "Create anyway";
    }, this.holdSecondsValue * 1000);
  }

  cancelHold() {
    this.clearHoldTimer();
    if (this.hasOverrideButtonTarget && this.overrideArmed) {
      this.overrideArmed = false;
      this.overrideButtonTarget.setAttribute("aria-disabled", "true");
      this.overrideButtonTarget.textContent = "Hold to confirm…";
    }
  }

  clearHoldTimer() {
    if (this.holdTimer) {
      window.clearTimeout(this.holdTimer);
      this.holdTimer = null;
    }
  }

  proceed() {
    if (!this.hasOverrideButtonTarget || !this.overrideArmed) return;
    this.setPrimaryDisabled(false);
    if (this.hasPrimaryButtonTarget) this.primaryButtonTarget.click();
  }
}
