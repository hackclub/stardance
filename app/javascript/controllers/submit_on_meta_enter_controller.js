import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  submit(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      const form = this.element.closest("form");
      if (form) form.requestSubmit();
    }
  }
}
