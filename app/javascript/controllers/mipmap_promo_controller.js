import { Controller } from "@hotwired/stimulus";

const SVG_NS = "http://www.w3.org/2000/svg";
// One turn every 12s, as on mipmap.hackclub.com.
const DEGREES_PER_SECOND = 30;
// How quickly the cogs ease toward the speed they're asked for.
const RESPONSE = 6;
// Hovering brakes the cogs, winds them backwards a little, then holds them still.
const STOP_MS = 450;
const REVERSE_MS = 700;
const REVERSE_SPEED = 0.6;
const REEL_SPEED = 12;
const SHOOT_MS = 420;
const SHOOT_STAGGER_MS = 60;
const PULL_MS = 1100;
const IRIS_MS = 700;
// A rope in flight droops by this share of its length, until reeling pulls it taut.
const SAG = 0.08;
const HOOK_RADIUS = 7;
// Where mipmap.hackclub.com lays out its logo, so the hand-off lands on the same spot.
const LANDING_TOP = 24;
const PHONE_WIDTH = 600;

export default class extends Controller {
  static targets = ["card", "logo"];

  connect() {
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.angle = 0;
    this.speed = 1;
    this.cogs = this.findCogs(this.logoTarget);

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
    document.removeEventListener("visibilitychange", this.onVisibility);
    window.removeEventListener("pageshow", this.onPageShow);
    cancelAnimationFrame(this.frame);
    this.running = false;
    this.clearOverlay();
  }

  findCogs(svg) {
    return [...svg.querySelectorAll(".mipmap-promo__cog")].map((el) => ({
      el,
      direction: el.classList.contains("mipmap-promo__cog--reverse") ? -1 : 1,
    }));
  }

  syncLoop() {
    if (this.reduceMotion) return;
    const shouldRun = this.launching || (this.visible && !document.hidden);
    if (shouldRun && !this.running) {
      this.running = true;
      this.lastTick = null;
      this.frame = requestAnimationFrame((t) => this.tick(t));
    } else if (!shouldRun && this.running) {
      this.running = false;
      cancelAnimationFrame(this.frame);
    }
  }

  tick(now) {
    if (!this.running) return;
    this.frame = requestAnimationFrame((t) => this.tick(t));
    const dt =
      this.lastTick == null ? 0 : Math.min(0.1, (now - this.lastTick) / 1000);
    this.lastTick = now;
    this.speed +=
      (this.targetSpeed(now) - this.speed) * (1 - Math.exp(-dt * RESPONSE));
    this.angle = (this.angle + this.speed * DEGREES_PER_SECOND * dt) % 360;
    for (const { el, direction } of this.cogs)
      el.style.transform = `rotate(${this.angle * direction}deg)`;
  }

  targetSpeed(now) {
    if (this.reelSpeed != null) return this.reelSpeed;
    if (this.brakedAt == null) return 1;
    const held = now - this.brakedAt;
    if (held < STOP_MS) return 0;
    if (held < STOP_MS + REVERSE_MS) return -REVERSE_SPEED;
    return 0;
  }

  brake() {
    this.brakedAt = performance.now();
  }

  release() {
    this.brakedAt = null;
  }

  async launch(event) {
    if (this.reduceMotion || this.launching) return;
    if (
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    )
      return;
    event.preventDefault();
    this.launching = true;
    this.syncLoop();

    const scene = this.buildScene();
    this.reelSpeed = 0;
    await this.shoot(scene);
    this.reelSpeed = REEL_SPEED;
    await this.pull(scene);
    this.reelSpeed = 1;
    await this.close(scene);
    window.location.assign(this.cardTarget.href);
  }

  // Lift a copy of the logo into a full-screen overlay, and aim a rope from each cog along the
  // way it's about to travel, out to the far edge of the screen.
  buildScene() {
    const from = rectOf(this.logoTarget);
    const to = landingRect(from.width / from.height);
    const anchors = this.cogs.map(({ el }) => {
      const box = el.getBoundingClientRect();
      return {
        x: (box.left + box.width / 2 - from.left) / from.width,
        y: (box.top + box.height / 2 - from.top) / from.height,
      };
    });

    this.overlay = document.createElement("div");
    this.overlay.className = "mipmap-promo__overlay";
    this.overlay.setAttribute("aria-hidden", "true");
    const ropeLayer = document.createElementNS(SVG_NS, "svg");
    ropeLayer.classList.add("mipmap-promo__ropes");
    const iris = document.createElement("div");
    iris.className = "mipmap-promo__iris";
    const logo = this.logoTarget.cloneNode(true);
    logo.removeAttribute("data-mipmap-promo-target");
    logo.classList.add("mipmap-promo__flying");
    this.overlay.append(ropeLayer, iris, logo);
    document.body.append(this.overlay);

    this.cogs = [...this.cogs, ...this.findCogs(logo)];
    this.logoTarget.classList.add("mipmap-promo__logo--launched");

    const ropes = anchors.map((anchor) => {
      const start = pointIn(from, anchor);
      const hook = edgeHit(start, pointIn(to, anchor));
      const line = document.createElementNS(SVG_NS, "path");
      line.classList.add("mipmap-promo__rope");
      const knot = document.createElementNS(SVG_NS, "circle");
      knot.classList.add("mipmap-promo__hook");
      knot.setAttribute("r", HOOK_RADIUS);
      ropeLayer.append(line, knot);
      return { anchor, hook, line, knot };
    });

    const scene = { from, to, ropes, logo, iris };
    this.place(scene, from);
    return scene;
  }

  place(scene, rect) {
    scene.rect = rect;
    scene.logo.style.left = `${rect.left}px`;
    scene.logo.style.top = `${rect.top}px`;
    scene.logo.style.width = `${rect.width}px`;
  }

  drawRope(rope, rect, reach, slack) {
    const start = pointIn(rect, rope.anchor);
    const tip = {
      x: start.x + (rope.hook.x - start.x) * reach,
      y: start.y + (rope.hook.y - start.y) * reach,
    };
    const droop = Math.hypot(tip.x - start.x, tip.y - start.y) * SAG * slack;
    const bendX = (start.x + tip.x) / 2;
    const bendY = (start.y + tip.y) / 2 + droop;
    rope.line.setAttribute(
      "d",
      `M${start.x} ${start.y}Q${bendX} ${bendY} ${tip.x} ${tip.y}`,
    );
    rope.knot.setAttribute("cx", tip.x);
    rope.knot.setAttribute("cy", tip.y);
  }

  shoot(scene) {
    const total = SHOOT_MS + SHOOT_STAGGER_MS * (scene.ropes.length - 1);
    return animate(total, (u) => {
      const elapsed = u * total;
      scene.ropes.forEach((rope, i) => {
        const flight = clamp((elapsed - i * SHOOT_STAGGER_MS) / SHOOT_MS);
        this.drawRope(rope, scene.from, easeOut(flight), 1);
      });
    });
  }

  // The cogs wind their ropes in, hauling the logo across the screen and stretching it to size.
  pull(scene) {
    const { from, to } = scene;
    return animate(PULL_MS, (u) => {
      const t = easeInOut(u);
      const rect = {
        left: lerp(from.left, to.left, t),
        top: lerp(from.top, to.top, t),
        width: lerp(from.width, to.width, t),
        height: lerp(from.height, to.height, t),
      };
      this.place(scene, rect);
      const slack = 1 - clamp(u / 0.25);
      for (const rope of scene.ropes) this.drawRope(rope, rect, 1, slack);
    });
  }

  // Mipmap's own dirt closes in from the edges until only the logo is left.
  close(scene) {
    const { rect, iris } = scene;
    const x = rect.left + rect.width / 2;
    const y = rect.top + rect.height / 2;
    const width = window.innerWidth;
    const height = window.innerHeight;
    const radius = Math.hypot(Math.max(x, width - x), Math.max(y, height - y));
    iris.style.setProperty("--mipmap-promo-iris-x", `${x}px`);
    iris.style.setProperty("--mipmap-promo-iris-y", `${y}px`);
    return animate(IRIS_MS, (u) => {
      iris.style.setProperty(
        "--mipmap-promo-iris",
        `${radius * (1 - easeIn(u))}px`,
      );
    });
  }

  // Coming back through the back/forward cache restores the page mid-launch.
  reset() {
    if (!this.launching) return;
    this.clearOverlay();
    this.logoTarget.classList.remove("mipmap-promo__logo--launched");
    this.cogs = this.findCogs(this.logoTarget);
    this.launching = false;
    this.reelSpeed = null;
    this.brakedAt = null;
    this.syncLoop();
  }

  clearOverlay() {
    this.overlay?.remove();
    this.overlay = null;
  }
}

function rectOf(element) {
  const { left, top, width, height } = element.getBoundingClientRect();
  return { left, top, width, height };
}

function landingRect(aspect) {
  const width = document.documentElement.clientWidth;
  const share = width <= PHONE_WIDTH ? 0.9 : 0.75;
  const logoWidth = Math.min(share * width, 0.7 * window.innerHeight * aspect);
  return {
    left: (width - logoWidth) / 2,
    top: LANDING_TOP,
    width: logoWidth,
    height: logoWidth / aspect,
  };
}

function pointIn(rect, anchor) {
  return {
    x: rect.left + anchor.x * rect.width,
    y: rect.top + anchor.y * rect.height,
  };
}

// Carry on from `from` through `via` until the ray leaves the screen.
function edgeHit(from, via) {
  let dx = via.x - from.x;
  let dy = via.y - from.y;
  if (Math.hypot(dx, dy) < 1) {
    dx = window.innerWidth / 2 - from.x;
    dy = window.innerHeight / 2 - from.y;
  }
  const reach = Math.min(
    dx > 0
      ? (window.innerWidth - from.x) / dx
      : dx < 0
        ? -from.x / dx
        : Infinity,
    dy > 0
      ? (window.innerHeight - from.y) / dy
      : dy < 0
        ? -from.y / dy
        : Infinity,
  );
  return { x: from.x + dx * reach, y: from.y + dy * reach };
}

function animate(ms, step) {
  return new Promise((resolve) => {
    let start;
    const frame = (now) => {
      start ??= now;
      const u = Math.min(1, (now - start) / ms);
      step(u);
      if (u < 1) requestAnimationFrame(frame);
      else resolve();
    };
    requestAnimationFrame(frame);
  });
}

const clamp = (value) => Math.min(1, Math.max(0, value));
const lerp = (a, b, t) => a + (b - a) * t;
const easeIn = (t) => t * t * t;
const easeOut = (t) => 1 - (1 - t) ** 3;
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
