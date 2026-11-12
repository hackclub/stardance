import { Controller } from "@hotwired/stimulus";

const TEXT_FIELD =
  "input:not([type=radio]):not([type=checkbox]), textarea, select";

// Single-key shortcuts. Pressing a key activates every element inside the
// controller whose data-hotkey matches: text fields are focused, everything
// else is clicked. Escape leaves the field being typed in.
//
//   <section data-controller="hotkeys" data-action="keydown@document->hotkeys#press">
//     <button data-hotkey="a">Approve</button>
export default class extends Controller {
  press(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (event.target.closest(`${TEXT_FIELD}, [contenteditable]`)) {
      if (event.key === "Escape") event.target.blur();
      return;
    }
    const matches = this.element.querySelectorAll(
      `[data-hotkey="${CSS.escape(event.key.toLowerCase())}"]`,
    );
    if (!matches.length) return;
    event.preventDefault();
    matches.forEach((element) =>
      element.matches(TEXT_FIELD) ? element.focus() : element.click(),
    );
  }
}
