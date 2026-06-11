import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["selectAll", "item", "count", "actions", "form"];

  toggle() {
    const checked = this.selectAllTarget.checked;
    this.itemTargets.forEach((cb) => (cb.checked = checked));
    this.sync();
  }

  changed() {
    const all = this.itemTargets;
    const checked = all.filter((cb) => cb.checked);
    this.selectAllTarget.checked = checked.length === all.length;
    this.selectAllTarget.indeterminate =
      checked.length > 0 && checked.length < all.length;
    this.sync();
  }

  sync() {
    const checked = this.itemTargets.filter((cb) => cb.checked);
    if (this.hasCountTarget) {
      this.countTarget.textContent = checked.length;
    }
    if (this.hasActionsTarget) {
      this.actionsTarget.hidden = checked.length === 0;
    }
    this.formTargets.forEach((form) => {
      form
        .querySelectorAll('input[name="referral_ids[]"]')
        .forEach((el) => el.remove());
      checked.forEach((cb) => {
        const hidden = document.createElement("input");
        hidden.type = "hidden";
        hidden.name = "referral_ids[]";
        hidden.value = cb.value;
        form.appendChild(hidden);
      });
    });
  }
}
