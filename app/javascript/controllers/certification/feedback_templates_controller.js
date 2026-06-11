import { Controller } from "@hotwired/stimulus";

const STORAGE_KEY = "certification-feedback-templates";

// Canned request-changes responses for the ship review form. Options carry
// their text in data-body; built-ins live in the "Standard" optgroup, and
// the Shipwright's own templates are kept in localStorage and rendered into
// the personal optgroup, where they can be saved and deleted without
// leaving the form.
export default class extends Controller {
  static targets = [
    "picker",
    "feedback",
    "returnedRadio",
    "personalGroup",
    "deleteButton",
  ];

  connect() {
    this.renderPersonal();
  }

  insert() {
    const option = this.pickerTarget.selectedOptions[0];
    this.syncDeleteButton();
    const body = option?.dataset.body;
    if (!body) return;

    if (
      this.feedbackTarget.value.trim() !== "" &&
      this.feedbackTarget.value !== this.lastInsertedBody &&
      !confirm("Replace your current feedback with the template?")
    ) {
      this.pickerTarget.value = "";
      this.syncDeleteButton();
      return;
    }

    this.feedbackTarget.value = body;
    this.lastInsertedBody = body;
    if (this.hasReturnedRadioTarget) this.returnedRadioTarget.checked = true;
    this.selectFirstBullet(body);
  }

  save() {
    const body = this.feedbackTarget.value.trim();
    if (body === "") {
      alert("Write the feedback you want to save first.");
      return;
    }
    const label = prompt("Name this template:")?.trim();
    if (!label) return;

    const templates = this.personalTemplates().filter((t) => t.label !== label);
    templates.push({ label, body });
    templates.sort((a, b) => a.label.localeCompare(b.label));
    this.storePersonal(templates);

    this.renderPersonal();
    this.selectPersonal(label);
    this.lastInsertedBody = body;
    this.syncDeleteButton();
  }

  delete() {
    const option = this.pickerTarget.selectedOptions[0];
    const label = option?.dataset.personal && option.textContent;
    if (!label) return;
    if (!confirm(`Delete your "${label}" template?`)) return;

    this.storePersonal(
      this.personalTemplates().filter((t) => t.label !== label),
    );
    this.renderPersonal();
    this.pickerTarget.value = "";
    this.syncDeleteButton();
  }

  renderPersonal() {
    this.personalGroupTarget.replaceChildren(
      ...this.personalTemplates().map((template) => {
        const option = document.createElement("option");
        option.textContent = template.label;
        option.dataset.body = template.body;
        option.dataset.personal = "true";
        return option;
      }),
    );
  }

  selectPersonal(label) {
    const option = [...this.personalGroupTarget.children].find(
      (o) => o.textContent === label,
    );
    if (option) option.selected = true;
  }

  // Only the Shipwright's own templates can be deleted, so the button is
  // hidden unless a personal one is selected.
  syncDeleteButton() {
    const option = this.pickerTarget.selectedOptions[0];
    this.deleteButtonTarget.hidden = !option?.dataset.personal;
  }

  // Highlight the first bullet so the reviewer can type the actual change
  // straight over the placeholder.
  selectFirstBullet(body) {
    this.feedbackTarget.focus();
    const match = body.match(/^- (.+)$/m);
    if (!match) return;
    const start = match.index + 2;
    this.feedbackTarget.setSelectionRange(start, start + match[1].length);
  }

  personalTemplates() {
    try {
      const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
      return parsed.filter((t) => t?.label && t?.body);
    } catch {
      return [];
    }
  }

  storePersonal(templates) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(templates));
  }
}
