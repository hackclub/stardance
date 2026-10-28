import { Controller } from "@hotwired/stimulus";
import confetti from "canvas-confetti";

const CONFETTI_COLORS = [
  "#81ffff", // mint
  "#ebb7ff", // lilac
  "#ff8d9d", // salmon
  "#ffe564", // yellow
  "#ffd598", // peach
];

// Fires a celebratory confetti burst once, when the element connects, then
// removes the element so a Turbo back/forward restore can't replay it. Used on
// My Orders right after an order is placed. Skipped for reduced motion.
export default class extends Controller {
  connect() {
    this.element.remove();
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const base = {
      colors: CONFETTI_COLORS,
      shapes: ["star", "square"],
      zIndex: 10000,
      ticks: 220,
    };
    confetti({
      ...base,
      particleCount: 80,
      angle: 60,
      spread: 60,
      startVelocity: 55,
      origin: { x: 0, y: 0.8 },
    });
    confetti({
      ...base,
      particleCount: 80,
      angle: 120,
      spread: 60,
      startVelocity: 55,
      origin: { x: 1, y: 0.8 },
    });
  }
}
