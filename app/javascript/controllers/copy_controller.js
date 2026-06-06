import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { text: String };

  copy(event) {
    event.preventDefault();
    const text = this.textValue;
    const tooltip = window.Stimulus?.getControllerForElementAndIdentifier(
      this.element,
      "tooltip",
    );

    const onDone = () => {
      if (!tooltip) return;
      tooltip.messageValue = "Copied!";
      tooltip.hide();
      tooltip.show();
      setTimeout(() => {
        tooltip.messageValue = "Click to copy";
        tooltip.hide();
      }, 1200);
    };

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard
        .writeText(text)
        .then(onDone)
        .catch(() => {
          this.#fallback(text);
          onDone();
        });
    } else {
      this.#fallback(text);
      onDone();
    }
  }

  #fallback(text) {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.style.cssText = "position:fixed;opacity:0";
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    ta.remove();
  }
}
