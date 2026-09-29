import { Controller } from "@hotwired/stimulus";

// Client-side filter for the /queue turnaround table. The whole table is
// already on the page, so filtering is a hidden-attribute toggle rather than
// another round trip.
export default class extends Controller {
  static targets = ["input", "row", "empty"];

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase();
    let matches = 0;

    this.rowTargets.forEach((row) => {
      const hit = !query || row.dataset.queueFilterName.includes(query);
      row.hidden = !hit;
      if (hit) matches += 1;
    });

    if (this.hasEmptyTarget) this.emptyTarget.hidden = matches > 0;
  }
}
