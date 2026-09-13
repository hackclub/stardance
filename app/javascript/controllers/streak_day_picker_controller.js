import { Controller } from "@hotwired/stimulus";

// Clicking a day in the admin credit calendar loads that date into the form's
// date field rather than crediting it outright, so the reason box and the
// submit button still gate the write.
export default class extends Controller {
  static targets = ["date"];

  static SELECTED_CLASS = "streak-calendar__cell--selected";

  pick(event) {
    const date = event.params.date;
    if (!this.hasDateTarget || !date) return;

    this.dateTarget.value = date;

    this.selected?.classList.remove(this.constructor.SELECTED_CLASS);
    this.selected = event.currentTarget;
    this.selected.classList.add(this.constructor.SELECTED_CLASS);
  }
}
