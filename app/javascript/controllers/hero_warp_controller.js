import { Controller } from "@hotwired/stimulus";

// Flips <html> from .warping to .warped so the CSS reveal cascade plays.
// The inline head-script sets .warping before first paint; this controller
// connects as soon as Stimulus boots and flips to .warped.
//
// Fallbacks:
//   - No JS → .warping never gets added; page renders normally.
//   - Prefers-reduced-motion is handled downstream in _warp.scss.
export default class extends Controller {
  connect() {
    const root = document.documentElement;
    root.classList.remove("warping");
    root.classList.add("warped");
  }
}
