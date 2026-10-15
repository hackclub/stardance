import { Controller } from "@hotwired/stimulus";

// Segmented six-box entry for certificate codes (letter/digit alternating)
// that behaves like a single text box: typing flows forward into the next
// box, backspace walks backward, arrows navigate, and focusing a filled box
// selects it so typing overwrites. Every change is mirrored into the hidden
// `code` field so the form submits a plain ?code=XXXXXX param.
export default class extends Controller {
  static targets = ["box", "code"];

  connect() {
    this.sync();
  }

  input(event) {
    const box = event.target;
    const index = this.boxTargets.indexOf(box);
    const chars = this.clean(box.value).split("");

    // Rewrite from the current box forward so multi-character input (fast
    // typing, mobile autocorrect, mid-code edits) lands one char per box.
    box.value = "";
    let cursor = index;
    chars.forEach((char) => {
      if (cursor >= this.boxTargets.length) return;
      this.boxTargets[cursor].value = char;
      cursor += 1;
    });

    if (chars.length) this.focusBox(cursor);
    this.sync();
  }

  keydown(event) {
    const index = this.boxTargets.indexOf(event.target);

    switch (event.key) {
      case "Backspace":
        event.preventDefault();
        if (event.target.value) {
          event.target.value = "";
        } else if (index > 0) {
          this.boxTargets[index - 1].value = "";
          this.focusBox(index - 1);
        }
        this.sync();
        break;
      case "ArrowLeft":
        event.preventDefault();
        this.focusBox(index - 1);
        break;
      case "ArrowRight":
        event.preventDefault();
        this.focusBox(index + 1);
        break;
    }
  }

  paste(event) {
    event.preventDefault();
    const chars = this.clean(event.clipboardData.getData("text"))
      .slice(0, this.boxTargets.length)
      .split("");
    this.boxTargets.forEach((box, index) => (box.value = chars[index] || ""));
    this.focusBox(chars.length);
    this.sync();
  }

  select(event) {
    event.target.select();
  }

  clean(value) {
    return (value || "").replace(/[^a-zA-Z0-9]/g, "").toUpperCase();
  }

  focusBox(index) {
    const clamped = Math.max(0, Math.min(index, this.boxTargets.length - 1));
    const box = this.boxTargets[clamped];
    box.focus();
    box.select();
  }

  sync() {
    this.codeTarget.value = this.boxTargets.map((box) => box.value).join("");
  }
}
