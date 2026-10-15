import { Controller } from "@hotwired/stimulus";
import BurntEdge from "../forge_promo/burnt_edge";
import FireWave from "../forge_promo/fire_wave";
import Sparks from "../forge_promo/sparks";

const MAX_DPR = 2;
const COLORS = ["core", "flame", "ember", "soot"];
// Sparks per CSS pixel of card width per second, at rest; hovering and clicking stoke it.
const SPARK_RATE = 0.08;
const STOKED_HEAT = 2;
const BLAZE_HEAT = 4;
const STILL_FRAMES = 90;
const RISE_MS = 1300;
// Once the whole screen is ablaze it roars a moment, then dies down to charred black, and only
// then leaves.
const HOLD_MS = 250;
const FADE_MS = 500;
// How high the wall's flames tower above its front, as a share of the screen's height. It starts
// that far below the screen and climbs until its front is a third of that above the top edge, so
// even the top of the screen is deep in the flames.
const WALL_HEIGHT = 0.7;

export default class extends Controller {
  static targets = ["card", "embers"];

  connect() {
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.colors = this.readColors();
    this.sparks = new Sparks(this.embersTarget, this.colors);
    this.edge = new BurntEdge();
    this.time = 0;
    this.heat = 1;
    this.targetHeat = 1;
    this.backlog = 0;

    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(this.embersTarget);
    this.onVisibility = () => this.syncLoop();
    document.addEventListener("visibilitychange", this.onVisibility);
    this.onPageShow = (event) => {
      if (event.persisted) this.reset();
    };
    window.addEventListener("pageshow", this.onPageShow);

    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting;
        this.syncLoop();
      },
      { rootMargin: "120px" },
    );
    this.observer.observe(this.element);
  }

  disconnect() {
    this.observer?.disconnect();
    this.resizeObserver?.disconnect();
    document.removeEventListener("visibilitychange", this.onVisibility);
    window.removeEventListener("pageshow", this.onPageShow);
    cancelAnimationFrame(this.frame);
    this.running = false;
    this.clearWave();
  }

  readColors() {
    const style = getComputedStyle(this.element);
    return Object.fromEntries(
      COLORS.map((name) => [
        name,
        style.getPropertyValue(`--forge-promo-${name}`).trim(),
      ]),
    );
  }

  // The canvas fills the whole widget, so sparks rise into the space around the card; note where the card sits in it.
  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    const canvas = this.embersTarget.getBoundingClientRect();
    const card = this.cardTarget.getBoundingClientRect();
    if (!canvas.width) return;
    this.dpr = dpr;
    this.sparks.resize(
      Math.round(canvas.width * dpr),
      Math.round(canvas.height * dpr),
    );
    this.card = {
      x: card.left - canvas.left,
      y: card.top - canvas.top,
      width: card.width,
      height: card.height,
    };
    this.burn(0);
    this.syncLoop();
  }

  syncLoop() {
    if (this.reduceMotion) {
      this.drawStill();
      return;
    }
    const shouldRun = this.card && this.visible && !document.hidden;
    if (shouldRun && !this.running) {
      this.running = true;
      this.lastTick = null;
      this.frame = requestAnimationFrame((t) => this.tick(t));
    } else if (!shouldRun && this.running) {
      this.running = false;
      cancelAnimationFrame(this.frame);
    }
  }

  drawStill() {
    if (!this.card) return;
    for (let i = 0; i < STILL_FRAMES; i++) {
      this.kindle(1 / 60);
      this.sparks.step(1 / 60);
    }
    this.sparks.draw((ctx) => this.char(ctx));
  }

  tick(now) {
    if (!this.running) return;
    this.frame = requestAnimationFrame((t) => this.tick(t));
    const dt =
      this.lastTick == null ? 0 : Math.min(0.1, (now - this.lastTick) / 1000);
    this.lastTick = now;
    this.heat += (this.targetHeat - this.heat) * (1 - Math.exp(-dt * 4));
    this.burn(dt);
    this.kindle(dt);
    this.sparks.step(dt);
    this.sparks.draw((ctx) => this.char(ctx));
  }

  // Creep the burnt outline along and cut the card to it.
  burn(dt) {
    this.time += dt * this.heat;
    this.outline = this.edge.trace(this.card.width, this.card.height, {
      time: this.time,
      heat: this.heat,
    });
    const path = this.outline
      .map(({ x, y }, i) => `${i ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`)
      .join("");
    this.cardTarget.style.clipPath = `path("${path}Z")`;
  }

  // Trace the burnt outline on the canvas, in canvas pixels.
  outlinePath(ctx) {
    const { x, y } = this.card;
    const dpr = this.dpr;
    ctx.beginPath();
    for (const point of this.outline)
      ctx.lineTo((x + point.x) * dpr, (y + point.y) * dpr);
    ctx.closePath();
  }

  // Scorch a dark band just inside the burnt edge, then make the edge itself glow like a smouldering rim.
  char(ctx) {
    const dpr = this.dpr;
    ctx.save();
    this.outlinePath(ctx);
    ctx.clip();
    ctx.strokeStyle = this.colors.soot;
    ctx.lineJoin = "round";
    for (const [width, alpha] of [
      [22, 0.35],
      [10, 0.6],
    ]) {
      ctx.lineWidth = width * dpr;
      ctx.globalAlpha = alpha;
      ctx.stroke();
    }
    ctx.restore();

    // The rim smoulders hottest low down, where the fire is, and is barely lit along the top.
    const rim = ctx.createLinearGradient(
      0,
      this.card.y * dpr,
      0,
      (this.card.y + this.card.height) * dpr,
    );
    rim.addColorStop(0, "transparent");
    rim.addColorStop(0.5, this.colors.ember);
    rim.addColorStop(1, this.colors.flame);
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    // Steady at rest; it only flickers, faintly, as hovering stokes the fire.
    const stoked = Math.min(
      1,
      Math.max(0, (this.heat - 1) / (STOKED_HEAT - 1)),
    );
    ctx.globalAlpha =
      0.6 + 0.1 * stoked * Math.sin(this.time * 3) * Math.sin(this.time * 1.7);
    ctx.strokeStyle = rim;
    ctx.shadowColor = this.colors.flame;
    ctx.shadowBlur = 10 * dpr;
    ctx.lineWidth = 1.5 * dpr;
    ctx.lineJoin = "round";
    ctx.stroke();
    ctx.restore();
  }

  // Throw sparks off the burnt edge, mostly low down where the fire has taken hold.
  kindle(dt) {
    const dpr = this.dpr;
    this.backlog += SPARK_RATE * this.heat * this.card.width * dt;
    for (; this.backlog >= 1; this.backlog--) {
      const point = this.pickBurning();
      this.sparks.emit({
        x: (this.card.x + point.x) * dpr,
        y: (this.card.y + point.y) * dpr,
        vx: (Math.random() - 0.5) * 30 * dpr,
        vy: -(50 + Math.random() * 60) * dpr,
        size: (1.5 + Math.random() * 2) * dpr,
        life: 1.6 + Math.random(),
        lift: 30 * dpr,
      });
    }
  }

  // Points low on the card are far likelier to be alight.
  pickBurning() {
    for (;;) {
      const point =
        this.outline[Math.floor(Math.random() * this.outline.length)];
      if (Math.random() < point.low ** 1.5 + 0.03) return point;
    }
  }

  stoke() {
    if (!this.blazing) this.targetHeat = STOKED_HEAT;
  }

  settle() {
    if (!this.blazing) this.targetHeat = 1;
  }

  async ignite(event) {
    if (this.reduceMotion || this.blazing) return;
    if (
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    )
      return;
    // Without WebGL there's no wave, so the link just goes to Forge.
    const wave = this.buildWave();
    if (!wave) return;
    event.preventDefault();
    this.blazing = true;
    this.targetHeat = BLAZE_HEAT;
    await this.sweep(wave);
    window.location.assign(this.cardTarget.href);
  }

  buildWave() {
    this.overlay = document.createElement("div");
    this.overlay.className = "forge-promo__overlay";
    const canvas = document.createElement("canvas");
    canvas.className = "forge-promo__wave";
    this.overlay.append(canvas);
    const wave = FireWave.create(canvas, this.colors);
    if (!wave) return null;
    this.wave = wave;
    const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    wave.resize(
      Math.round(window.innerWidth * dpr),
      Math.round(window.innerHeight * dpr),
      dpr,
    );
    document.body.append(this.overlay);
    return wave;
  }

  // A wall of fire climbs the screen from the bottom, then dies down and leaves it charred black.
  sweep(wave) {
    const reach = window.innerHeight * WALL_HEIGHT;
    const from = window.innerHeight + reach;
    const to = -reach / 3;
    return new Promise((resolve) => {
      let start;
      const frame = (now) => {
        start ??= now;
        const elapsed = now - start;
        const rise = Math.min(1, elapsed / RISE_MS);
        const fade = Math.min(
          1,
          Math.max(0, (elapsed - RISE_MS - HOLD_MS) / FADE_MS),
        );
        wave.draw({
          time: elapsed / 1000,
          front: from + (to - from) * rise,
          reach,
          fade,
        });
        if (fade < 1) requestAnimationFrame(frame);
        else resolve();
      };
      requestAnimationFrame(frame);
    });
  }

  // Coming back through the back/forward cache restores the page mid-blaze.
  reset() {
    if (!this.blazing) return;
    this.clearWave();
    this.blazing = false;
    this.targetHeat = 1;
  }

  clearWave() {
    this.wave?.destroy();
    this.wave = null;
    this.overlay?.remove();
    this.overlay = null;
  }
}
