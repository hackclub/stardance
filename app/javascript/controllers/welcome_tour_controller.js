import { Controller } from "@hotwired/stimulus";
import confetti from "canvas-confetti";

const CONFETTI_COLORS = [
  "#81ffff", // mint
  "#ebb7ff", // lilac
  "#ff8d9d", // salmon
  "#ffe564", // yellow
  "#ffd598", // peach
];

export default class extends Controller {
  static targets = [
    "spotlight",
    "tooltip",
    "text",
    "subtitle",
    "back",
    "next",
    "counter",
  ];

  static values = {
    step: { type: Number, default: 0 },
    steps: Array,
    minWidth: { type: Number, default: 900 },
    lockScroll: { type: Boolean, default: true },
    // When set, finishing the tour records a server-side dismissal so it
    // doesn't show again (via POST /my/dismissals).
    dismissThing: { type: String, default: "" },
  };

  connect() {
    if (window.innerWidth < this.minWidthValue) {
      this._abort();
      return;
    }

    this._onReflow = this._onReflow.bind(this);
    this._onKey = this._onKey.bind(this);
    this._onDocumentClick = this._onDocumentClick.bind(this);

    window.addEventListener("resize", this._onReflow);
    window.addEventListener("scroll", this._onReflow, { passive: true });
    document.addEventListener("keydown", this._onKey);
    document.addEventListener("click", this._onDocumentClick, true);
    // Lets an outside trigger (e.g. the shop's inline "Ok, I'll do it!" button)
    // dismiss the tour, which still records the server-side dismissal.
    this._onExternalDismiss = () => this.finish();
    document.addEventListener("welcome-tour:dismiss", this._onExternalDismiss);

    if (this.lockScrollValue) {
      this._previousOverflow = document.body.style.overflow;
      document.body.style.overflow = "hidden";
    }

    this._render();
    requestAnimationFrame(() => {
      this.element.classList.add("welcome-tour--ready");
    });
  }

  disconnect() {
    this._clearAutoAdvance();
    window.removeEventListener("resize", this._onReflow);
    window.removeEventListener("scroll", this._onReflow);
    document.removeEventListener("keydown", this._onKey);
    document.removeEventListener("click", this._onDocumentClick, true);
    document.removeEventListener("welcome-tour:dismiss", this._onExternalDismiss);
    this._clearWaitForTarget();
    if (this._previousOverflow !== undefined) {
      document.body.style.overflow = this._previousOverflow;
    }
  }

  stepValueChanged() {
    if (!this.hasSpotlightTarget) return;
    this._clearAutoAdvance();
    this._render();
  }

  next() {
    this._clearAutoAdvance();
    this._advancing = false;
    this._clearWaitForTarget();
    if (this.stepValue >= this.stepsValue.length - 1) {
      this.finish();
    } else {
      this.stepValue += 1;
    }
  }

  back() {
    this._clearAutoAdvance();
    if (this.stepValue > 0) this.stepValue -= 1;
  }

  finish() {
    this._clearAutoAdvance();
    this._clearWaitForTarget();
    if (this.dismissThingValue) this._recordDismissal(this.dismissThingValue);
    this.element.remove();
  }

  _recordDismissal(thing) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    fetch("/my/dismissals", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
      },
      body: JSON.stringify({ thing_name: thing }),
    }).catch(() => {});
  }

  _clearAutoAdvance() {
    if (this._autoAdvanceTimer) {
      clearTimeout(this._autoAdvanceTimer);
      this._autoAdvanceTimer = null;
    }
    if (this._confettiTimer) {
      clearTimeout(this._confettiTimer);
      this._confettiTimer = null;
    }
  }

  _onReflow() {
    this._render();
  }

  _onKey(event) {
    const step = this.stepsValue[this.stepValue];
    // clickToAdvance steps lock the user to a specific action — don't let
    // them skip past it with Escape or arrow keys.
    if (step?.clickToAdvance) return;

    if (event.key === "Escape") {
      this.finish();
    } else if (event.key === "ArrowRight") {
      this.next();
    } else if (event.key === "ArrowLeft") {
      this.back();
    }
  }

  _onDocumentClick(event) {
    const step = this.stepsValue[this.stepValue];
    if (!step?.clickToAdvance || this._advancing) return;

    const target = this._findTarget(step.selector);
    if (!target) return;
    if (target !== event.target && !target.contains(event.target)) return;

    this._advancing = true;
    // Wait for the turbo frame swap that the click usually triggers before
    // advancing — the next step's target lives in the freshly-loaded frame
    // and `waitForTarget` will pick it up once it appears. Use a single
    // `advance` callback wired to both signals so they can't double-fire.
    let advanced = false;
    let timeoutId;
    const advance = () => {
      if (advanced) return;
      advanced = true;
      clearTimeout(timeoutId);
      document.removeEventListener("turbo:frame-load", advance);
      this.next();
    };
    document.addEventListener("turbo:frame-load", advance, { once: true });
    timeoutId = setTimeout(advance, 2500);
  }

  _render() {
    const step = this.stepsValue[this.stepValue];
    if (!step) {
      this.finish();
      return;
    }

    this.element.classList.toggle("welcome-tour--intro", !!step.intro);
    this.element.classList.toggle(
      "welcome-tour--ceremonial",
      !!step.ceremonial,
    );
    this.element.classList.remove("welcome-tour--ceremonial-leaving");
    this.element.classList.toggle(
      "welcome-tour--click-to-advance",
      !!step.clickToAdvance,
    );

    if (this.hasSubtitleTarget) {
      if (step.subtitle) {
        this.subtitleTarget.textContent = step.subtitle;
        this.subtitleTarget.hidden = false;
      } else {
        this.subtitleTarget.textContent = "";
        this.subtitleTarget.hidden = true;
      }
    }

    if (step.intro) {
      this._renderIntro(step);
      return;
    }

    const target = this._findTarget(step.selector);
    if (!target) {
      if (step.waitForTarget) {
        this._scheduleWaitForTarget();
        return;
      }
      if (this.stepValue < this.stepsValue.length - 1) {
        this.stepValue += 1;
      } else {
        this.finish();
      }
      return;
    }
    this._clearWaitForTarget();

    // Bring the highlighted target to the vertical middle of the viewport the
    // first time we render it (scroll reflow re-runs _render, repositioning
    // the spotlight to follow).
    if (step.scrollToCenter && !this._scrolledToCenter) {
      this._scrolledToCenter = true;
      target.scrollIntoView({ block: "center", behavior: "smooth" });
    }

    const pad = step.padding ?? 12;
    const rect = target.getBoundingClientRect();

    let top = rect.top - pad;
    const bottom = rect.bottom + pad;

    if (step.excludeTop) {
      const excluded = this._findTarget(step.excludeTop);
      if (excluded) {
        const excludedRect = excluded.getBoundingClientRect();
        const floor = excludedRect.bottom + (step.excludeGap ?? 0);
        if (floor > top) top = floor;
      }
    }

    const left = rect.left - pad;
    const width = rect.width + pad * 2;
    let height = bottom - top;
    if (step.maxHeight) {
      height = Math.min(height, step.maxHeight);
    }
    const radius = step.radius ?? 12;

    Object.assign(this.spotlightTarget.style, {
      top: `${top}px`,
      left: `${left}px`,
      width: `${width}px`,
      height: `${height}px`,
      borderRadius: `${radius}px`,
    });

    this.textTarget.textContent = step.text;

    // Counter shows position among user-clickable steps only — auto-advance
    // (ceremonial intro) doesn't count as a step the user can navigate.
    const autoBeforeMe = this.stepsValue
      .slice(0, this.stepValue)
      .filter((s) => s.autoAdvance).length;
    const visibleIndex = this.stepValue - autoBeforeMe;
    const visibleTotal = this.stepsValue.filter((s) => !s.autoAdvance).length;
    this.counterTarget.textContent = `${visibleIndex + 1}/${visibleTotal}`;

    const isLast = visibleIndex === visibleTotal - 1;
    this.nextTarget.textContent =
      step.nextLabel ||
      (isLast ? "Finish! →" : `Next (${visibleIndex + 1}/${visibleTotal}) →`);
    this.nextTarget.hidden = !!step.clickToAdvance;
    this.backTarget.hidden = this.stepValue === 0 || !!step.clickToAdvance;

    this.element.classList.toggle(
      "welcome-tour--arrow-bottom",
      step.arrowPosition === "bottom",
    );
    this._positionTooltip(
      top,
      left,
      width,
      height,
      step.placement,
      step.arrowPosition,
    );
    this._applyPlacementClass(step.placement);
  }

  _applyPlacementClass(placement = "right") {
    this.element.classList.remove(
      "welcome-tour--placement-right",
      "welcome-tour--placement-left",
      "welcome-tour--placement-above",
      "welcome-tour--placement-below",
    );
    this.element.classList.add(
      `welcome-tour--placement-${this._lastResolvedPlacement || placement}`,
    );
  }

  _renderIntro(step) {
    Object.assign(this.spotlightTarget.style, {
      top: `${window.innerHeight / 2}px`,
      left: `${window.innerWidth / 2}px`,
      width: "0px",
      height: "0px",
      borderRadius: "0px",
    });

    this.textTarget.textContent = step.text;
    this.counterTarget.textContent = `${this.stepValue + 1}/${this.stepsValue.length}`;

    const isLast = this.stepValue === this.stepsValue.length - 1;
    this.nextTarget.textContent = isLast
      ? "Finish! →"
      : `Next (${this.stepValue + 1}/${this.stepsValue.length}) →`;
    this.backTarget.hidden = this.stepValue === 0;

    // On auto-advance steps the user shouldn't need to click — hide the nav
    // and let the timer take us to the next step.
    const auto = !!step.autoAdvance;
    this.nextTarget.hidden = auto;
    if (auto) this.backTarget.hidden = true;

    const tooltip = this.tooltipTarget;
    const tooltipRect = tooltip.getBoundingClientRect();
    Object.assign(tooltip.style, {
      top: `${Math.max(16, window.innerHeight / 2 - tooltipRect.height / 2)}px`,
      left: `${Math.max(16, window.innerWidth / 2 - tooltipRect.width / 2)}px`,
    });

    if (auto) {
      const FADE_OUT_MS = 500;

      // Fire confetti immediately as the welcome ceremony starts — bursts
      // appear against the black veil while the welcome text fades in.
      if (step.ceremonial) {
        this._fireConfetti();
      }

      // Trigger a fade-out class first, then advance once the animation has
      // had time to play. Both timers are tracked via _autoAdvanceTimer so
      // _clearAutoAdvance/next/back can cancel them at any point.
      this._autoAdvanceTimer = setTimeout(() => {
        this.element.classList.add("welcome-tour--ceremonial-leaving");
        this._autoAdvanceTimer = setTimeout(() => this.next(), FADE_OUT_MS);
      }, step.autoAdvance);
    }
  }

  _fireConfetti() {
    if (typeof confetti !== "function") return;

    const base = {
      colors: CONFETTI_COLORS,
      zIndex: 10000,
      shapes: ["star", "square"],
      ticks: 220,
    };

    // Two cannons from the lower corners arcing toward the middle.
    confetti({
      ...base,
      particleCount: 70,
      angle: 60,
      spread: 58,
      startVelocity: 55,
      origin: { x: 0, y: 0.85 },
      scalar: 1.05,
    });
    confetti({
      ...base,
      particleCount: 70,
      angle: 120,
      spread: 58,
      startVelocity: 55,
      origin: { x: 1, y: 0.85 },
      scalar: 1.05,
    });

    // A slow drift of stars falling from above, sustained for ~1.4s so the
    // burst tapers into something gentler instead of cutting off hard.
    const driftEnd = performance.now() + 1400;
    const drift = () => {
      confetti({
        ...base,
        particleCount: 3,
        startVelocity: 0,
        gravity: 0.5,
        ticks: 320,
        shapes: ["star"],
        scalar: 0.85,
        origin: { x: Math.random(), y: -0.05 },
      });
      if (performance.now() < driftEnd) {
        this._confettiTimer = setTimeout(drift, 110);
      }
    };
    drift();
  }

  _findTarget(selector) {
    for (const candidate of selector.split(",")) {
      const el = document.querySelector(candidate.trim());
      if (el) return el;
    }
    return null;
  }

  _positionTooltip(
    top,
    left,
    width,
    height,
    placement = "right",
    arrowPosition = "top",
  ) {
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const tooltip = this.tooltipTarget;
    const gap = 48;
    const minGap = 12;
    const margin = 16;
    const minWidth = 240;

    // Reset any prior width override so the tooltip measures at its natural size.
    tooltip.style.width = "";
    const naturalWidth = tooltip.getBoundingClientRect().width;

    const right = left + width;
    const bottom = top + height;

    const roomRight = vw - right - minGap - margin;
    const roomLeft = left - minGap - margin;

    const fitsRight = roomRight >= naturalWidth;
    const fitsLeft = roomLeft >= naturalWidth;
    const canShrinkRight = roomRight >= minWidth;
    const canShrinkLeft = roomLeft >= minWidth;

    let resolved = placement;
    if (placement === "right" && !fitsRight) {
      if (canShrinkRight) resolved = "right-shrink";
      else if (fitsLeft) resolved = "left";
      else if (canShrinkLeft) resolved = "left-shrink";
      else resolved = "below";
    }
    if (placement === "left" && !fitsLeft) {
      if (canShrinkLeft) resolved = "left-shrink";
      else if (fitsRight) resolved = "right";
      else if (canShrinkRight) resolved = "right-shrink";
      else resolved = "below";
    }
    if (placement === "above" || placement === "below") {
      resolved = placement;
    }

    let tooltipLeft;
    let tooltipTop;
    let appliedWidth = null;

    if (resolved === "left" || resolved === "left-shrink") {
      appliedWidth = resolved === "left-shrink" ? roomLeft : naturalWidth;
      tooltipLeft =
        left - appliedWidth - (resolved === "left-shrink" ? minGap : gap);
    } else if (resolved === "below") {
      appliedWidth = naturalWidth;
      tooltipLeft = left + width / 2 - appliedWidth / 2;
      tooltipTop = bottom + gap;
    } else if (resolved === "above") {
      appliedWidth = naturalWidth;
      tooltipLeft = left + width / 2 - appliedWidth / 2;
    } else {
      // right or right-shrink
      appliedWidth = resolved === "right-shrink" ? roomRight : naturalWidth;
      tooltipLeft = right + (resolved === "right-shrink" ? minGap : gap);
    }

    if (appliedWidth && appliedWidth !== naturalWidth) {
      tooltip.style.width = `${appliedWidth}px`;
    }

    const finalRect = tooltip.getBoundingClientRect();

    if (resolved === "above") {
      tooltipTop = top - gap - finalRect.height;
    } else if (resolved !== "below") {
      // Align the arrow's pointing end with the target's vertical center.
      // The arrow's tip is ~42px from whichever edge of the tooltip it sits on.
      const ARROW_TIP_OFFSET = 42;
      if (arrowPosition === "bottom") {
        tooltipTop = top + height / 2 - finalRect.height + ARROW_TIP_OFFSET;
      } else {
        tooltipTop = top + height / 2 - ARROW_TIP_OFFSET;
      }
    }

    this._lastResolvedPlacement = resolved.replace("-shrink", "");

    if (tooltipLeft < margin) tooltipLeft = margin;
    if (tooltipLeft + finalRect.width + margin > vw) {
      tooltipLeft = vw - finalRect.width - margin;
    }
    if (tooltipTop < margin) tooltipTop = margin;
    if (tooltipTop + finalRect.height + margin > vh) {
      tooltipTop = vh - finalRect.height - margin;
    }

    Object.assign(tooltip.style, {
      top: `${tooltipTop}px`,
      left: `${tooltipLeft}px`,
    });
  }

  _abort() {
    this.element.remove();
  }

  _scheduleWaitForTarget() {
    if (this._waitForTargetTimer) return;
    this._waitForTargetStart = Date.now();
    this._waitForTargetTimer = setInterval(() => {
      const step = this.stepsValue[this.stepValue];
      if (!step) {
        this._clearWaitForTarget();
        return;
      }
      const target = this._findTarget(step.selector);
      if (target) {
        this._clearWaitForTarget();
        target.scrollIntoView({ block: "center", behavior: "smooth" });
        this._render();
        return;
      }
      if (Date.now() - this._waitForTargetStart > 8000) {
        this._clearWaitForTarget();
        if (this.stepValue < this.stepsValue.length - 1) this.next();
        else this.finish();
      }
    }, 120);
  }

  _clearWaitForTarget() {
    if (this._waitForTargetTimer) {
      clearInterval(this._waitForTargetTimer);
      this._waitForTargetTimer = null;
    }
  }
}
