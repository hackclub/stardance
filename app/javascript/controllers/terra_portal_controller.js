import { Controller } from "@hotwired/stimulus";
import ShaderRing from "../terra_portal/shader_ring";
import SmokeRing from "../terra_portal/smoke_ring";

// Matches the 70% solid stop in .terra-portal__aperture's mask.
const CLEAR = 0.7;
const COMPOSITE_SIZE = 2048;
const MAX_DPR = 2;
const SURGE_SPEED = 6;
const SURGE_LEAD_MS = 450;
const ZOOM_MS = 1500;
const STILL_TIME_S = 12;
const COLORS = ["deep", "mid", "hi", "glint"];

export default class extends Controller {
  static targets = ["stage", "aperture", "view", "canvas"];
  static values = { image: String };

  connect() {
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.time = this.reduceMotion ? STILL_TIME_S : 0;
    this.speed = 1;
    this.targetSpeed = 1;
    this.ring = this.buildRing();
    this.ring.setColors(this.readColors());
    this.magnify = parseFloat(
      getComputedStyle(this.element).getPropertyValue("--terra-portal-magnify"),
    );
    this.ring.setMagnify(this.magnify);

    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(this.stageTarget);
    this.onVisibility = () => this.syncLoop();
    document.addEventListener("visibilitychange", this.onVisibility);
    this.onWindowResize = () => {
      clearTimeout(this.compositeTimer);
      this.compositeTimer = setTimeout(() => this.refreshDestination(), 200);
    };
    window.addEventListener("resize", this.onWindowResize);
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
    this.loadImage();
  }

  disconnect() {
    this.observer?.disconnect();
    this.resizeObserver?.disconnect();
    document.removeEventListener("visibilitychange", this.onVisibility);
    window.removeEventListener("resize", this.onWindowResize);
    window.removeEventListener("pageshow", this.onPageShow);
    clearTimeout(this.compositeTimer);
    cancelAnimationFrame(this.frame);
    this.running = false;
    this.ring.destroy();
    if (this.viewUrl) URL.revokeObjectURL(this.viewUrl);
  }

  // A canvas stays bound to WebGL once asked, even if the shader then fails, so the fallback gets a fresh one.
  buildRing() {
    const shader = ShaderRing.create(this.canvasTarget);
    if (shader) return shader;
    const canvas = this.canvasTarget.cloneNode();
    this.canvasTarget.replaceWith(canvas);
    return new SmokeRing(canvas);
  }

  readColors() {
    const style = getComputedStyle(this.element);
    return Object.fromEntries(
      COLORS.map((name) => [
        name,
        toRgb(style.getPropertyValue(`--terra-portal-${name}`)),
      ]),
    );
  }

  async loadImage() {
    const image = new Image();
    image.src = this.imageValue;
    try {
      await image.decode();
    } catch {
      return;
    }
    this.image = image;
    this.refreshDestination();
  }

  // The portal shows the screenshot framed exactly as it will fill this viewport, so it depends on the window size.
  refreshDestination() {
    if (!this.image || this.warping) return;
    const composite = buildComposite(this.image);
    this.ring.setDestination(composite);
    composite.toBlob(
      (blob) => {
        if (this.viewUrl) URL.revokeObjectURL(this.viewUrl);
        this.viewUrl = URL.createObjectURL(blob);
        this.viewTarget.src = this.viewUrl;
      },
      "image/jpeg",
      0.92,
    );
    this.ready = true;
    this.syncLoop();
  }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    const size = Math.round(this.stageTarget.clientWidth * dpr);
    if (!size || size === this.size) return;
    this.size = size;
    this.ring.resize(size);
    this.syncLoop();
  }

  drawStill() {
    if (!this.ready) return;
    for (let i = 0; i < 90; i++)
      this.ring.draw({
        time: this.time + i / 60,
        step: 1 / 60,
        dt: 1 / 60,
        surge: 0,
      });
  }

  syncLoop() {
    if (this.reduceMotion) {
      this.drawStill();
      return;
    }
    const shouldRun =
      this.ready && this.size && this.visible && !document.hidden;
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
    this.speed += (this.targetSpeed - this.speed) * (1 - Math.exp(-dt * 2.5));
    const step = dt * this.speed;
    this.time += step;
    this.ring.draw({
      time: this.time,
      step,
      dt,
      surge: (this.speed - 1) / (SURGE_SPEED - 1),
    });
  }

  async enter(event) {
    if (this.reduceMotion || this.warping || !this.ready) return;
    if (
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    )
      return;
    event.preventDefault();
    this.warping = true;
    this.warmUp();
    this.targetSpeed = SURGE_SPEED;
    this.ring.openHole();
    await wait(SURGE_LEAD_MS);

    const zoom = this.lockPage();
    await animate(ZOOM_MS, (u) => {
      this.applyZoom(zoom, easeInOut(u));
      this.element.style.setProperty(
        "--terra-portal-fx",
        Math.max(0, (1 - u) / 0.3),
      );
    });
    this.arrive();
    window.location.assign(this.stageTarget.href);
  }

  // Boot Terra out of sight during the zoom so its immutable scripts and images are cached
  // by the time the tab navigates. Both sites are on hackclub.com, so they share a cache partition.
  warmUp() {
    this.warmup = document.createElement("iframe");
    this.warmup.className = "terra-portal__warmup";
    this.warmup.src = this.stageTarget.href;
    this.warmup.tabIndex = -1;
    this.warmup.title = "Terra";
    this.warmup.setAttribute("aria-hidden", "true");
    document.body.append(this.warmup);
  }

  // Transforming <html> pins fixed elements (sidebar, rail) to the document instead of the viewport,
  // so swap the window scroll for an equal body offset before zooming.
  lockPage() {
    const root = document.documentElement;
    const { body } = document;
    this.scrollY = window.scrollY;
    if (window.innerWidth > root.clientWidth)
      root.style.scrollbarGutter = "stable";
    root.style.overflow = "hidden";
    body.style.position = "relative";
    body.style.top = `${-this.scrollY}px`;
    window.scrollTo({ top: 0, behavior: "instant" });
    root.style.transformOrigin = "0 0";

    const view = this.apertureTarget.getBoundingClientRect();
    const width = root.clientWidth;
    const height = root.clientHeight;
    return {
      x: view.left + view.width / 2,
      y: view.top + view.height / 2,
      cx: width / 2,
      cy: height / 2,
      scale: Math.hypot(width, height) / (view.width * CLEAR),
    };
  }

  // Scale exponentially about the portal so its clear circle ends up covering the viewport,
  // sliding the portal to the viewport's centre on the way. The magnification eases out
  // alongside so the screenshot arrives at true size.
  applyZoom(zoom, progress) {
    const s = Math.exp(Math.log(zoom.scale) * progress);
    const k = (s - 1) / (zoom.scale - 1);
    const tx = zoom.x * (1 - s) + (zoom.cx - zoom.x) * k;
    const ty = zoom.y * (1 - s) + (zoom.cy - zoom.y) * k;
    document.documentElement.style.transform = `translate(${tx}px, ${ty}px) scale(${s})`;
    const magnify = this.magnify ** (1 - progress);
    this.element.style.setProperty("--terra-portal-magnify", magnify);
    this.ring.setMagnify(magnify);
  }

  // Swap the scaled-up portal for the full-resolution screenshot while the next page loads.
  arrive() {
    this.arrival = document.createElement("img");
    this.arrival.className = "terra-portal__arrival";
    this.arrival.alt = "";
    this.arrival.src = this.imageValue;
    document.body.append(this.arrival);
    document.documentElement.style.removeProperty("transform");
  }

  // Coming back through the back/forward cache restores the page mid-warp.
  reset() {
    if (!this.warping) return;
    const root = document.documentElement;
    this.arrival?.remove();
    this.warmup?.remove();
    for (const prop of [
      "transform",
      "transform-origin",
      "overflow",
      "scrollbar-gutter",
    ])
      root.style.removeProperty(prop);
    document.body.style.removeProperty("position");
    document.body.style.removeProperty("top");
    window.scrollTo({ top: this.scrollY, behavior: "instant" });
    this.element.style.removeProperty("--terra-portal-fx");
    this.element.style.removeProperty("--terra-portal-magnify");
    this.ring.setMagnify(this.magnify);
    this.targetSpeed = 1;
    this.ring.closeHole();
    this.warping = false;
  }
}

// Square texture: the screenshot framed to the viewport and inscribed in the clear circle,
// surrounded by blurred mirror copies so the rest of the hole has something to show.
function buildComposite(image) {
  const { clientWidth: vw, clientHeight: vh } = document.documentElement;
  const diag = Math.hypot(vw, vh);
  const n = COMPOSITE_SIZE;
  const rw = Math.round((n * CLEAR * vw) / diag);
  const rh = Math.round((n * CLEAR * vh) / diag);

  const framed = document.createElement("canvas");
  framed.width = rw;
  framed.height = rh;
  const scale = Math.max(rw / image.naturalWidth, rh / image.naturalHeight);
  const iw = image.naturalWidth * scale;
  const ih = image.naturalHeight * scale;
  framed
    .getContext("2d")
    .drawImage(image, (rw - iw) / 2, (rh - ih) / 2, iw, ih);

  const composite = document.createElement("canvas");
  composite.width = composite.height = n;
  const ctx = composite.getContext("2d");
  ctx.filter = "blur(24px) brightness(0.7)";
  for (let i = -2; i <= 2; i++) {
    for (let j = -2; j <= 2; j++) {
      ctx.save();
      ctx.translate(n / 2 + i * rw, n / 2 + j * rh);
      ctx.scale(i % 2 ? -1 : 1, j % 2 ? -1 : 1);
      ctx.drawImage(framed, -rw / 2, -rh / 2);
      ctx.restore();
    }
  }
  ctx.filter = "none";
  ctx.drawImage(framed, (n - rw) / 2, (n - rh) / 2);
  return composite;
}

let colorProbe;
function toRgb(color) {
  colorProbe ??= document
    .createElement("canvas")
    .getContext("2d", { willReadFrequently: true });
  colorProbe.clearRect(0, 0, 1, 1);
  colorProbe.fillStyle = color.trim();
  colorProbe.fillRect(0, 0, 1, 1);
  const [r, g, b] = colorProbe.getImageData(0, 0, 1, 1).data;
  return [r / 255, g / 255, b / 255];
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const easeInOut = (u) =>
  u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;

function animate(duration, step) {
  return new Promise((resolve) => {
    const start = performance.now();
    requestAnimationFrame(function frame(now) {
      const u = Math.min(1, (now - start) / duration);
      step(u);
      if (u < 1) requestAnimationFrame(frame);
      else resolve();
    });
  });
}
