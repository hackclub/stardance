import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dialog"];
  static values = { key: String };

  connect() {
    this.dialogTarget.showModal();
    document.body.style.overflow = "hidden";
  }

  dismiss() {
    this.#persistDismissal();
    this.dialogTarget.close();
    document.body.style.overflow = "";
    this.element.remove();
  }

  async dismissAndNavigate(event) {
    event.preventDefault();
    const href = event.currentTarget.href;
    await this.#persistDismissal();
    window.location.href = href;
  }

  #persistDismissal() {
    const token = document.querySelector("meta[name='csrf-token']")?.content;
    return fetch("/my/dismissals", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
      },
      body: JSON.stringify({ thing_name: this.keyValue }),
    }).catch(() => {});
  }
}
