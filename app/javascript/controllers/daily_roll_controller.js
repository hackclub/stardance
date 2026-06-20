import { Controller } from "@hotwired/stimulus";

// Reveal animation for the rng widget. When the server streams the widget
// back with just-rolled=true the real number unveils one digit at a time
// from the ones place — each digit rolls slowly before it locks, and the
// number keeps growing until it just stops — then the whole number slams
// home. Shake, stars.
export default class extends Controller {
  static targets = ["number", "burst"];
  static values = {
    justRolled: Boolean,
    value: Number,
    // BEM block the reveal classes hang off, so the same animation can drive
    // the rail widget (daily-roll-widget) and the /rng hero (rng-hero).
    baseClass: { type: String, default: "daily-roll-widget" },
  };

  // Each incoming digit rolls through this many random values before locking;
  // kept slow so the one-at-a-time growth is easy to follow.
  static SPIN_FRAMES = 6;
  static SPIN_FRAME_MS = 80;
  static SUSPENSE_MS = 500;
  static PARTICLE_COUNT = 14;

  connect() {
    if (!this.justRolledValue || !this.hasNumberTarget) return;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.land();
      return;
    }

    this.alive = true;
    this.element.classList.add(`${this.base}--rolling`);
    this.reveal();
  }

  disconnect() {
    this.alive = false;
    clearTimeout(this.sleepTimer);
  }

  get base() {
    return this.baseClassValue;
  }

  async reveal() {
    const digits = String(Math.abs(this.valueValue));
    this.buildSlots();

    // Unveil from the ones place, one digit at a time. Each incoming digit
    // rolls through random values before it locks onto the front; the number
    // keeps growing until it just stops. Comma groups count from the right,
    // so the partial number is always formatted correctly.
    let revealed = "";
    for (let i = digits.length - 1; i >= 0; i--) {
      if (!this.alive) return;
      for (let frame = 0; frame < this.constructor.SPIN_FRAMES; frame++) {
        this.digitsElement.textContent = this.group(
          this.randomDigit() + revealed,
        );
        await this.sleep(this.constructor.SPIN_FRAME_MS);
      }
      revealed = digits[i] + revealed;
      this.digitsElement.textContent = this.group(revealed);
      this.tick();
      await this.sleep(this.constructor.SPIN_FRAME_MS);
    }

    // It stopped. Beat of suspense, then it slams home.
    await this.sleep(this.constructor.SUSPENSE_MS);
    if (!this.alive) return;
    this.slam();
    this.land();
  }

  buildSlots() {
    this.numberTarget.textContent = "";

    this.digitsElement = document.createElement("span");
    this.digitsElement.className = `${this.base}__digits`;

    this.numberTarget.append(this.digitsElement);
  }

  // Restartable bump on each locked digit.
  tick() {
    this.digitsElement.classList.remove(`${this.base}__digits--tick`);
    void this.digitsElement.offsetWidth;
    this.digitsElement.classList.add(`${this.base}__digits--tick`);
  }

  // The climax: the assembled number rears back and slams into place.
  slam() {
    this.numberTarget.classList.add(`${this.base}__number--slammed`);
  }

  // Final state: full styled number visible, flavor + leaderboard fade in.
  land() {
    if (!this.digitsElement) {
      this.numberTarget.textContent = this.group(String(this.valueValue));
    }
    this.element.classList.remove(
      `${this.base}--waiting`,
      `${this.base}--rolling`,
    );
    this.element.classList.add(`${this.base}--landed`);
    this.burstStars();
  }

  burstStars() {
    if (!this.hasBurstTarget) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const intMax = 2147483647;
    const count =
      Math.abs(this.valueValue) >= intMax * 0.9
        ? this.constructor.PARTICLE_COUNT
        : Math.ceil(this.constructor.PARTICLE_COUNT / 2);

    for (let i = 0; i < count; i++) {
      const star = document.createElement("span");
      star.className = `${this.base}__particle`;
      star.textContent = "✦";
      star.style.setProperty(
        "--angle",
        `${(360 / count) * i + Math.random() * 24}deg`,
      );
      star.style.setProperty("--dist", `${40 + Math.random() * 40}px`);
      star.style.setProperty("--delay", `${Math.random() * 90}ms`);
      star.addEventListener("animationend", () => star.remove());
      this.burstTarget.appendChild(star);
    }
  }

  randomDigit() {
    return String(Math.floor(Math.random() * 10));
  }

  // "1234567" -> "1,234,567"; works on partial suffixes with leading zeros.
  group(s) {
    return s.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }

  sleep(ms) {
    return new Promise((resolve) => {
      this.sleepTimer = setTimeout(resolve, ms);
    });
  }
}
