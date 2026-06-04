import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  dismiss(event) {
    event.stopPropagation();

    const token = document.querySelector("meta[name='csrf-token']")?.content;
    fetch("/my/dismissals", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
      },
      body: JSON.stringify({ thing_name: "slack_doodle" }),
    }).catch(() => {});

    this.element.remove();
  }
}
