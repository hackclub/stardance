import { Controller } from "@hotwired/stimulus";

// Asks the server whether this project's repo is already in the unified YSWS DB
// under another program, then reveals the sidebar warning. Runs after page load
// because the lookup hits Airtable — the review page must not wait on it.
export default class extends Controller {
  static targets = ["warning", "programs"];
  static values = { url: String };
  static classes = ["outline"];

  connect() {
    this.check();
  }

  async check() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
      });

      if (!response.ok) {
        console.warn(`[double-dip] check failed: HTTP ${response.status}`);
        return;
      }

      const data = await response.json();
      if (!data.double_dipped) return;

      if (this.hasProgramsTarget && data.programs_label) {
        this.programsTarget.textContent = data.programs_label;
      }
      this.warningTarget.hidden = false;
      this.element.classList.add(...this.outlineClasses);
    } catch (error) {
      console.warn("[double-dip] check failed", error);
    }
  }
}
