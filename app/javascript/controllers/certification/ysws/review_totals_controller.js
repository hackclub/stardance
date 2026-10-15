import { Controller } from "@hotwired/stimulus";

// Keeps the Time Stats "Time Deducted" box in step with the devlog decision
// panels below it, which save over JSON and so never re-render this card.
//
// Only the current review's devlogs are editable — cards from prior (frozen)
// reviews render without a controller or data values, so their share of the
// deduction arrives from the server as frozenMinutes and is held constant.
//
// Values:
//   - frozenMinutes: deducted minutes from read-only prior reviews
//
// Targets:
//   - deducted: the stat value element to write the total into
//
// Actions:
//   - refresh: recompute the total (bound to devlog-review:saved@window)

const CARD = '[data-controller~="certification--ysws--devlog-review"]';
const ORIGINAL =
  "data-certification--ysws--devlog-review-original-minutes-value";
const STATUS = "data-certification--ysws--devlog-review-status-value";

export default class extends Controller {
  static targets = ["deducted"];

  static values = { frozenMinutes: Number };

  connect() {
    this.refresh();
  }

  refresh() {
    let minutes = this.frozenMinutesValue;

    document.querySelectorAll(CARD).forEach((card) => {
      // Undecided devlogs have deducted nothing yet.
      if (card.getAttribute(STATUS) === "pending") return;

      const original = Number(card.getAttribute(ORIGINAL)) || 0;
      const approved = Number(card.querySelector(".minutes-input")?.value) || 0;

      // Clamped per card so a bump on one devlog can't cancel a cut on another.
      minutes += Math.max(0, original - approved);
    });

    this.deductedTarget.textContent = `${(minutes / 60).toFixed(1)}h`;
  }
}
