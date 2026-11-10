import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "field",
    "form",
    "preview",
    "previewButton",
    "bulkInput",
    "bulkStatus",
  ];

  beforeCache() {
    this.bulkInputTarget.value = "";
    this.bulkChanged();
  }

  bulkChanged() {
    this.clear();
    this.bulkSelections?.forEach(({ field, previous }) => {
      if (field.checked) previous.checked = true;
    });
    this.bulkSelections = [];
    this.bulkStatusTarget.textContent = "";
    this.bulkInputTarget.removeAttribute("aria-invalid");
    if (!this.bulkInputTarget.value.trim()) return;

    try {
      const rows = JSON.parse(this.bulkInputTarget.value);
      if (!Array.isArray(rows)) {
        throw new Error("Paste a JSON array of devlog IDs and phases.");
      }
      const seen = new Set();
      const fields = rows.map((row) => {
        if (
          !row ||
          typeof row !== "object" ||
          Array.isArray(row) ||
          Object.keys(row).sort().join(",") !== "id,phase" ||
          !["string", "number"].includes(typeof row.id) ||
          (typeof row.id === "number" && !Number.isSafeInteger(row.id)) ||
          !/^[1-9]\d*$/.test(String(row.id)) ||
          !["design", "build"].includes(row.phase)
        ) {
          throw new Error(
            'Each entry must have only "id" and "phase" ("design" or "build").',
          );
        }
        const id = String(row.id);
        if (seen.has(id))
          throw new Error(`Devlog #${id} appears more than once.`);
        seen.add(id);
        const field = this.fieldTargets.find(
          (input) =>
            input.type === "radio" &&
            input.name === `phases[${id}]` &&
            input.value === row.phase,
        );
        if (!field)
          throw new Error(
            `Devlog #${id} is not an editable devlog on this project.`,
          );
        return field;
      });
      // Validate the whole batch before changing any selection.
      this.bulkSelections = fields.map((field) => ({
        field,
        previous: this.fieldTargets.find(
          (input) => input.name === field.name && input.checked,
        ),
      }));
      fields.forEach((field) => (field.checked = true));
      this.bulkStatusTarget.textContent = rows.length
        ? `${rows.length} devlog selection(s) loaded. Review the payout preview before saving.`
        : "No phase corrections listed.";
      this.reset();
    } catch (error) {
      this.bulkInputTarget.setAttribute("aria-invalid", "true");
      this.bulkStatusTarget.textContent =
        error instanceof SyntaxError
          ? "Invalid JSON. Paste an array like the example above."
          : error.message;
    }
  }

  disconnect() {
    clearTimeout(this.timer);
  }

  scrollToPreview() {
    this.formTarget.scrollIntoView({ block: "start" });
  }

  clear() {
    clearTimeout(this.timer);
    this.previewTarget.textContent = "No changes selected.";
    this.previewButtonTarget.hidden = true;
    this.fieldTargets.forEach((field) => (field.disabled = false));
  }

  reset() {
    this.clear();
    if (
      !this.fieldTargets.some(
        (field) =>
          field.type === "radio" && field.checked && !field.defaultChecked,
      )
    )
      return;

    this.previewTarget.textContent = "Calculating payout changes…";
    this.timer = setTimeout(() => this.formTarget.requestSubmit(), 300);
  }

  start() {
    this.previewTarget.textContent = "Calculating payout changes…";
    this.previewButtonTarget.hidden = true;
    this.focusedField = this.fieldTargets.find(
      (field) => field === document.activeElement,
    );
    // Keep the visible selection equal to the signed preview while it loads.
    // Turbo has already collected the form data before submit-start fires.
    this.fieldTargets.forEach((field) => (field.disabled = true));
  }

  finish({ detail }) {
    if (!detail.fetchResponse) this.failed();
  }

  loaded() {
    this.fieldTargets.forEach((field) => (field.disabled = false));
    if (document.activeElement === document.body)
      this.focusedField?.focus({ preventScroll: true });
    this.previewButtonTarget.hidden =
      !this.previewTarget.querySelector("[role=alert]");
  }

  failed(event) {
    event?.preventDefault();
    this.clear();
    this.previewButtonTarget.hidden = false;
    this.previewTarget.textContent =
      "Couldn’t calculate the changes. Try again.";
  }
}
