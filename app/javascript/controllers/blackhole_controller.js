import { Controller } from "@hotwired/stimulus";
import { Delaunay } from "d3";

const CARD_SURFACES =
  ".feed-post-card, .feed-composer, .rocket-progress, .rail-widget, .raffle-widget, .sidebar__logo-img, .sidebar__user-card";
const MEDIA_CONTENT = "img, video, iframe, svg";
const SIDEBAR_SURFACES = [
  "#primary-nav",
  ".sidebar__logo-img",
  ".sidebar__user-card",
];
// Story scenes must remain intact even at 100% damage, including previews
// inserted into the page after the effect has already started.
const EXCLUDED_SCENES = ".visual-novel, .buku-x3-reveal";
const PROTECTED_CONTENT =
  "a:not(.feed-post-card__overlay-link), button, input, textarea, select, summary, img, video, iframe, svg, [role='progressbar'], [role='meter'], [contenteditable]";
const SVG_NS = "http://www.w3.org/2000/svg";
const SIMULATOR_KEY = "stardance-event-simulator-v1";
const clamp = (n, min = 0, max = 1) => Math.min(max, Math.max(min, n));
const random = (x, y, seed = 0) => {
  const value = Math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453;
  return value - Math.floor(value);
};
const noise = (x, y, seed) => {
  const ix = Math.floor(x),
    iy = Math.floor(y);
  const fx = x - ix,
    fy = y - iy;
  const u = fx * fx * (3 - 2 * fx),
    v = fy * fy * (3 - 2 * fy);
  return (
    (random(ix, iy, seed) * (1 - u) + random(ix + 1, iy, seed) * u) * (1 - v) +
    (random(ix, iy + 1, seed) * (1 - u) + random(ix + 1, iy + 1, seed) * u) * v
  );
};

// SVG clipping removes pieces of the live DOM without changing its contents.
// Live intensity and the visual safety control are server-owned.
export default class extends Controller {
  static values = {
    intensity: Number,
    visualIntensity: { type: Number, default: 100 },
    progressUrl: String,
    awaitingReveal: Boolean,
    particlesEnabled: { type: Boolean, default: true },
    simulatorEnabled: Boolean,
  };

  static targets = [
    "masks",
    "canvas",
    "text",
    "simulatorForm",
    "simulatorStatus",
  ];

  connect() {
    this.simulation = null;
    if (this.simulatorEnabledValue && this.hasSimulatorFormTarget) {
      try {
        const saved = JSON.parse(sessionStorage.getItem(SIMULATOR_KEY));
        if (saved) {
          for (const field of this.simulatorFormTarget.elements) {
            if (field.disabled || !(field.name in saved)) continue;
            if (field.type === "checkbox")
              field.checked = saved[field.name] === true;
            else field.value = saved[field.name];
          }
          this.readSimulation();
        }
      } catch {
        /* Storage may be unavailable; the preview still works. */
      }
    }
    this.repairRadius = 145;
    this.pointer = null;
    this.level = 0;
    this.requested = 0;
    this.particles = [];
    this.surfaces = new Map();
    this.canvasContext = this.canvasTarget.getContext("2d");
    this.textRevision = 0;
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const style = getComputedStyle(this.element);
    this.particleColor = style
      .getPropertyValue("--color-brand-off-white")
      .trim();
    this.invalidate = () => {
      this.dirty = true;
      this.wake();
    };
    this.onScroll = this.invalidate;
    this.onPointerMove = (event) => {
      if (!this.requested || event.pointerType === "touch") return;
      this.pointer = { x: event.clientX, y: event.clientY };
      this.repairDirty = true;
      if (this.reducedMotion.matches) this.dirty = true;
      this.wake();
    };
    this.onPointerLeave = (event) => {
      if (event.type === "pointerout" && event.relatedTarget) return;
      this.pointer = null;
      this.repairDirty = true;
      if (this.reducedMotion.matches) this.dirty = true;
      this.wake();
    };
    this.resize = () => {
      this.sizeCanvas();
      this.invalidate();
    };
    this.beforeCache = () => {
      this.stopPolling();
      this.reset();
    };
    this.visibility = () => {
      if (document.hidden) {
        cancelAnimationFrame(this.frame);
        this.frame = null;
      } else this.invalidate();
    };
    window.addEventListener("pointermove", this.onPointerMove, {
      passive: true,
    });
    window.addEventListener("pointerout", this.onPointerLeave);
    window.addEventListener("blur", this.onPointerLeave);
    window.addEventListener("resize", this.resize);
    window.addEventListener("scroll", this.onScroll, {
      passive: true,
      capture: true,
    });
    document.addEventListener("turbo:before-cache", this.beforeCache);
    document.addEventListener("visibilitychange", this.visibility);
    document.addEventListener("turbo:frame-load", this.invalidate);
    this.observer = new MutationObserver((records) => {
      if (records.some((record) => !this.element.contains(record.target))) {
        const blocked = this.scenesBlocked();
        if (blocked !== this.sceneBlocked) {
          this.setIntensity(this.latestIntensity);
        }
        this.textRevision++;
        this.invalidate();
      }
    });
    this.observer.observe(document.body, {
      childList: true,
      characterData: true,
      subtree: true,
    });
    this.surfaceResize = new ResizeObserver(this.invalidate);
    this.sizeCanvas();
    this.setIntensity(this.intensityValue, { immediate: true });
    if (this.simulatorEnabledValue) {
      // Status controllers elsewhere on the page connect in the same turn.
      this.simulatorFrame = requestAnimationFrame(() =>
        this.setIntensity(this.latestIntensity),
      );
    }
    if (this.progressUrlValue) {
      this.pollTimer = window.setInterval(() => this.refreshProgress(), 60000);
      this.refreshProgress();
    }
  }

  disconnect() {
    cancelAnimationFrame(this.simulatorFrame);
    this.stopPolling();
    this.reset();
    this.observer.disconnect();
    this.surfaceResize.disconnect();
    window.removeEventListener("pointermove", this.onPointerMove);
    window.removeEventListener("pointerout", this.onPointerLeave);
    window.removeEventListener("blur", this.onPointerLeave);
    window.removeEventListener("resize", this.resize);
    window.removeEventListener("scroll", this.onScroll, true);
    document.removeEventListener("turbo:before-cache", this.beforeCache);
    document.removeEventListener("visibilitychange", this.visibility);
    document.removeEventListener("turbo:frame-load", this.invalidate);
  }

  stopPolling() {
    window.clearInterval(this.pollTimer);
    this.progressRequest?.abort();
    this.progressRequest = null;
  }

  async refreshProgress() {
    if (document.hidden || this.progressRequest) return;
    const request = new AbortController();
    this.progressRequest = request;
    try {
      const response = await fetch(this.progressUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        signal: request.signal,
      });
      if (request.signal.aborted || !this.element.isConnected) return;
      if (response.status === 401 || response.status === 403) {
        this.setIntensity(0);
        this.stopPolling();
        return;
      }
      if (!response.ok) return;
      const progress = await response.json();
      if (
        !request.signal.aborted &&
        this.element.isConnected &&
        Number.isFinite(progress.percent)
      ) {
        this.teamHours = progress.hours;
        if (Number.isFinite(progress.visual_intensity))
          this.visualIntensityValue = clamp(progress.visual_intensity, 0, 200);
        this.setIntensity(progress.percent);
      }
    } catch (error) {
      // Retain the last known state while offline; retry on the next tick.
      if (error.name !== "AbortError")
        console.debug("buku progress unavailable");
    } finally {
      if (this.progressRequest === request) this.progressRequest = null;
    }
  }

  setIntensity(value, { immediate = false } = {}) {
    if (!Number.isFinite(value)) return;
    this.latestIntensity = value;
    this.sceneBlocked = this.scenesBlocked();
    const damage = clamp((this.simulation?.damage ?? value) / 100);
    // Scale the visuals without changing the score sent to the tug-of-war.
    const strength =
      (this.simulation?.strength ?? this.visualIntensityValue ?? 100) / 100;
    this.requested = clamp(damage * strength);
    if (this.progressUrlValue || this.simulatorEnabledValue) {
      this.dispatch("progress", {
        detail: {
          percent: damage * 100,
          hours: this.simulation
            ? { buku: this.simulation.buku, bean: this.simulation.bean }
            : this.teamHours,
        },
      });
    }
    if (this.sceneBlocked || this.requested === 0) {
      this.reset();
      return;
    }
    // Navigation restores the current damage, not a fresh destruction scene.
    // Live updates and the first role reveal still ease into their new level.
    if (immediate) {
      this.level = this.requested;
      this.cutSurfaces(false);
    }
    this.dirty = !immediate;
    this.wake();
  }

  scenesBlocked() {
    return (
      (this.awaitingRevealValue && !this.simulation) ||
      !!document.querySelector(EXCLUDED_SCENES)
    );
  }

  readSimulation() {
    const fields = this.simulatorFormTarget.elements;
    const number = (name, max) =>
      clamp(Number(fields.namedItem(name).value) || 0, 0, max);
    this.simulation = {
      damage: number("damage", 100),
      buku: number("buku", 1000000),
      bean: number("bean", 1000000),
      strength: number("strength", 200),
      particles: fields.namedItem("particles").checked,
      cursorRepair: fields.namedItem("cursorRepair").checked,
    };
    this.simulatorStatusTarget.textContent = `${this.simulation.damage}% damaged · ${this.simulation.strength}% visual intensity · preview active`;
  }

  simulate(event) {
    event.preventDefault();
    if (!this.simulatorEnabledValue || !this.hasSimulatorFormTarget) return;
    const fields = this.simulatorFormTarget.elements;
    if (["buku", "bean"].includes(event.target.name)) {
      const buku = Math.max(0, Number(fields.namedItem("buku").value) || 0);
      const bean = Math.max(0, Number(fields.namedItem("bean").value) || 0);
      fields.namedItem("damage").value = clamp(25 + (buku - bean) / 50, 0, 100);
    }
    this.readSimulation();
    this.particles = [];
    this.dustBudget = 0;
    try {
      sessionStorage.setItem(SIMULATOR_KEY, JSON.stringify(this.simulation));
    } catch {
      /* Optional storage. */
    }
    this.setIntensity(this.latestIntensity);
  }

  resetSimulation() {
    if (!this.simulatorEnabledValue) return;
    this.simulation = null;
    this.particles = [];
    this.simulatorFormTarget.reset();
    this.simulatorStatusTarget.textContent = "live event values";
    try {
      sessionStorage.removeItem(SIMULATOR_KEY);
    } catch {
      /* Optional storage. */
    }
    this.setIntensity(this.latestIntensity);
    if (this.progressUrlValue) this.refreshProgress();
  }

  revealComplete() {
    this.awaitingRevealValue = false;
    // The scene may still be fading out; its removal will resume the effect.
    this.setIntensity(this.latestIntensity);
  }

  sizeCanvas() {
    this.width = window.innerWidth;
    this.height = window.innerHeight;
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    this.canvasTarget.width = this.width * ratio;
    this.canvasTarget.height = this.height * ratio;
    this.canvasContext.setTransform(ratio, 0, 0, ratio, 0, 0);
  }

  wake() {
    if (!this.requested && !this.level) return;
    if (!this.frame && !document.hidden)
      this.frame = requestAnimationFrame((time) => this.tick(time));
  }

  tick(time) {
    this.frame = null;
    const dt = Math.min((time - (this.lastTime || time)) / 1000, 0.05);
    this.lastTime = time;
    const previous = this.level;
    this.level = this.reducedMotion.matches
      ? this.requested
      : this.level + (this.requested - this.level) * (1 - Math.exp(-dt * 5));
    if (Math.abs(this.level - this.requested) < 0.001)
      this.level = this.requested;
    if (
      this.dirty ||
      ((this.repairActive || this.repairDirty) &&
        time - (this.lastMask || 0) > 45) ||
      (this.level !== previous &&
        (this.level === this.requested || time - (this.lastMask || 0) > 45))
    ) {
      this.cutSurfaces(this.level > previous);
      this.lastMask = time;
      this.dirty = false;
      this.repairDirty = false;
    }
    this.emitAmbientDust(dt);
    this.draw(dt);
    if (
      ((this.level > 0 &&
        this.particlesEnabledValue &&
        this.simulation?.particles !== false) ||
        this.repairActive ||
        this.repairDirty ||
        this.level !== this.requested ||
        this.particles.length) &&
      !this.reducedMotion.matches
    )
      this.wake();
  }

  collectSurfaces() {
    for (const [element, surface] of this.surfaces) {
      if (!element.isConnected) {
        this.surfaceResize.unobserve(element);
        surface.clip.remove();
        surface.textClip?.remove();
        surface.textCopy?.remove();
        this.surfaces.delete(element);
      }
    }
    // The layout wrapper is transparent: clip its columns separately so the
    // fixed discover rail never inherits the scrolling feed's holes.
    const cards = [...document.querySelectorAll(CARD_SURFACES)].filter(
      (element) =>
        !this.element.contains(element) &&
        !element.parentElement.closest(CARD_SURFACES),
    );
    const layers = [...document.body.children].flatMap((element) =>
      element.matches(".app-layout") ? [...element.children] : [element],
    );
    const elements = new Set([...layers, ...cards]);
    for (const element of elements) {
      if (
        element === this.element ||
        element.closest(EXCLUDED_SCENES) ||
        this.surfaces.has(element) ||
        element.matches(
          "script, style, link, svg, template, noscript, .app-loading",
        ) ||
        element.id.startsWith("rack-mini-profiler")
      )
        continue;
      const rect = element.getBoundingClientRect();
      if (!rect.width || !rect.height) continue;
      const clip = document.createElementNS(SVG_NS, "clipPath");
      clip.id = `blackhole-cut-${crypto.randomUUID()}`;
      clip.setAttribute("clipPathUnits", "userSpaceOnUse");
      const path = document.createElementNS(SVG_NS, "path");
      path.setAttribute("clip-rule", "evenodd");
      clip.append(path);
      this.masksTarget.firstElementChild.append(clip);
      this.surfaces.set(element, {
        clip,
        path,
        original: element.style.getPropertyValue("clip-path"),
        priority: element.style.getPropertyPriority("clip-path"),
        seed: this.surfaceSeed(element),
        card: cards.includes(element),
      });
      element.style.setProperty("clip-path", `url(#${clip.id})`);
      this.surfaceResize.observe(element);
    }
  }

  surfaceSeed(element) {
    // Permanent sidebar fragments must not depend on the current page's cards.
    const index = SIDEBAR_SURFACES.findIndex((selector) =>
      element.matches(selector),
    );
    return index < 0 ? this.surfaces.size * 31 : -(index + 1) * 31;
  }

  cutSurfaces(emit) {
    this.collectSurfaces();
    this.repairTime = performance.now();
    this.repairActive = false;
    this.textTarget.hidden = this.level <= 0.82;
    for (const surface of this.surfaces.values()) {
      if (surface.textCopy) surface.textCopy.hidden = true;
    }
    this.fringe = [];
    this.dustBounds = [];
    for (const [element, surface] of this.surfaces) {
      const rect = element.getBoundingClientRect();
      if (
        rect.bottom < 0 ||
        rect.top > this.height ||
        rect.right < 0 ||
        rect.left > this.width
      )
        continue;
      this.dustBounds.push({
        left: Math.max(0, rect.left),
        right: Math.min(this.width, rect.right),
        top: Math.max(0, rect.top),
        bottom: Math.min(this.height, rect.bottom),
      });
      let layer = element;
      while (layer.parentElement && getComputedStyle(layer).zIndex === "auto")
        layer = layer.parentElement;
      const seed =
        (Number.parseInt(getComputedStyle(layer).zIndex, 10) || 0) +
        surface.seed;
      surface.layerIndex = getComputedStyle(layer).zIndex;
      // Parent layers leave each card to its own mask, avoiding double erosion
      // while the cursor repair pocket restores nearby fragments.
      const nestedCards = surface.card
        ? []
        : [...element.querySelectorAll(CARD_SURFACES)];
      const excludedRects = nestedCards.map((card) =>
        this.localRect(card.getBoundingClientRect(), rect, 12),
      );
      const protectedRects = this.protectedRects(element, rect, nestedCards);

      const path = this.fragmentPath(
        rect,
        9,
        seed,
        protectedRects,
        excludedRects,
        surface.card,
      );
      surface.path.setAttribute("d", path);
      if (this.level > 0.82) this.drawDamagedText(element, rect, path, surface);
    }
    if (emit && !this.reducedMotion.matches) this.emitDust(8);
  }

  localRect(rect, surfaceRect, padding = 5) {
    return {
      left: rect.left - surfaceRect.left - padding,
      right: rect.right - surfaceRect.left + padding,
      top: rect.top - surfaceRect.top - padding,
      bottom: rect.bottom - surfaceRect.top + padding,
    };
  }

  protectedRects(element, surfaceRect, nestedCards = []) {
    const rects = [];
    const add = (rect, kind = "content") => {
      if (!rect.width || !rect.height) return;
      rects.push({ ...this.localRect(rect, surfaceRect), kind });
    };
    // Protect complete interactive/media areas, and each rendered text line.
    // The post's invisible full-card link must not shield the whole border.
    if (element.matches(MEDIA_CONTENT)) add(surfaceRect, "image");
    element.querySelectorAll(PROTECTED_CONTENT).forEach((child) => {
      if (nestedCards.some((card) => card.contains(child))) return;
      for (const rect of child.getClientRects())
        add(rect, child.matches(MEDIA_CONTENT) ? "image" : "content");
    });
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    const range = document.createRange();
    while (walker.nextNode()) {
      if (
        !walker.currentNode.textContent.trim() ||
        nestedCards.some((card) => card.contains(walker.currentNode))
      )
        continue;
      range.selectNodeContents(walker.currentNode);
      for (const rect of range.getClientRects()) add(rect, "text");
    }
    return rects;
  }

  drawDamagedText(element, rect, path, surface) {
    if (!surface.textClip) {
      surface.textClip = document.createElementNS(SVG_NS, "clipPath");
      surface.textClip.id = `blackhole-text-${crypto.randomUUID()}`;
      surface.textClip.setAttribute("clipPathUnits", "userSpaceOnUse");
      surface.textPath = document.createElementNS(SVG_NS, "path");
      surface.textClip.append(surface.textPath);
      this.masksTarget.firstElementChild.append(surface.textClip);
    }
    // Use native DOM glyphs so font shaping, line wrapping, and partial letters
    // match exactly. The inert, aria-hidden copy never handles interaction.
    if (!surface.textCopy || surface.textRevision !== this.textRevision) {
      surface.textCopy?.remove();
      const copy = element.cloneNode(true);
      const originals = [element, ...element.querySelectorAll("*")];
      const clones = [copy, ...copy.querySelectorAll("*")];
      surface.scrollCopies = [];
      originals.forEach((original, index) => {
        const clone = clones[index];
        for (const attribute of [...clone.attributes]) {
          if (
            attribute.name === "id" ||
            attribute.name.startsWith("data-") ||
            attribute.name.startsWith("on")
          )
            clone.removeAttribute(attribute.name);
        }
        if (
          original.matches("script, style, link, iframe, video, audio, source")
        ) {
          clone.remove();
          return;
        }
        if (original.matches("turbo-frame")) {
          clone.removeAttribute("src");
          clone.setAttribute("disabled", "");
        }
        if (
          original.scrollHeight > original.clientHeight ||
          original.scrollWidth > original.clientWidth
        )
          surface.scrollCopies.push([original, clone]);
        // Nested cards have their own mask/copy. Keep their space in the parent
        // layout without painting their contents a second time.
        if (original !== element && original.matches(CARD_SURFACES))
          clone.classList.add("blackhole__text-excluded");
        if (original.matches("img")) {
          const mediaRect = original.getBoundingClientRect();
          clone.style.width = `${mediaRect.width}px`;
          clone.style.height = `${mediaRect.height}px`;
          clone.removeAttribute("srcset");
          clone.removeAttribute("src");
        }
        if (original.matches("input, textarea, select"))
          clone.value = original.value;
      });
      const style = getComputedStyle(element);
      for (const property of [
        "font-family",
        "font-size",
        "font-weight",
        "font-style",
        "line-height",
        "letter-spacing",
        "word-spacing",
        "text-align",
        "direction",
      ])
        copy.style.setProperty(property, style.getPropertyValue(property));
      copy.classList.add("blackhole__text-copy");
      copy.inert = true;
      copy.setAttribute("aria-hidden", "true");
      this.textTarget.append(copy);
      surface.textCopy = copy;
      surface.textRevision = this.textRevision;
    }
    const copy = surface.textCopy;
    copy.hidden = false;
    copy.style.left = `${rect.left}px`;
    copy.style.top = `${rect.top}px`;
    copy.style.width = `${rect.width}px`;
    copy.style.height = `${rect.height}px`;
    copy.style.zIndex = surface.layerIndex;
    copy.style.clipPath = `url(#${surface.textClip.id})`;
    copy.scrollTop = element.scrollTop;
    copy.scrollLeft = element.scrollLeft;
    for (const [original, clone] of surface.scrollCopies) {
      clone.scrollTop = original.scrollTop;
      clone.scrollLeft = original.scrollLeft;
    }
    // The complementary path paints off-white glyphs only inside actual holes.
    surface.textPath.setAttribute(
      "d",
      !path
        ? `M0,0H${rect.width}V${rect.height}H0Z`
        : path.slice(path.indexOf("Z") + 1),
    );
  }

  fragmentCells(rect, size, seed) {
    // Deterministic sites with a wide guard band keep the same Voronoi cells
    // when scrolling. Cache the mesh while only intensity is changing.
    const left = Math.floor(Math.max(-rect.left, -size) / size) - 1;
    const right =
      Math.ceil(Math.min(this.width - rect.left, rect.width + size) / size) + 1;
    const top = Math.floor(Math.max(-rect.top, -size) / size) - 1;
    const bottom =
      Math.ceil(Math.min(this.height - rect.top, rect.height + size) / size) +
      1;
    const key = `${left}:${right}:${top}:${bottom}:${size}`;
    this.fragmentMeshes ||= new Map();
    const cached = this.fragmentMeshes.get(seed);
    if (cached?.key === key) return cached.cells;
    const sites = [];
    for (let y = top - 4; y <= bottom + 4; y++) {
      for (let x = left - 4; x <= right + 4; x++) {
        sites.push([
          (x + random(x, y, seed + 2)) * size,
          (y + random(x, y, seed + 3)) * size,
        ]);
      }
    }
    const voronoi = Delaunay.from(sites).voronoi([
      (left - 5) * size,
      (top - 5) * size,
      (right + 5) * size,
      (bottom + 5) * size,
    ]);
    const cells = [];
    sites.forEach(([cx, cy], index) => {
      if (
        cx < left * size ||
        cx > right * size ||
        cy < top * size ||
        cy > bottom * size
      )
        return;
      const polygon = voronoi.cellPolygon(index);
      if (!polygon) return;
      const vertices = polygon.slice(0, -1);
      cells.push({
        cx,
        cy,
        vertices,
        bounds: {
          left: Math.min(...vertices.map(([px]) => px)),
          right: Math.max(...vertices.map(([px]) => px)),
          top: Math.min(...vertices.map(([, py]) => py)),
          bottom: Math.max(...vertices.map(([, py]) => py)),
        },
      });
    });
    this.fragmentMeshes.set(seed, { key, cells });
    return cells;
  }

  fragmentPath(
    rect,
    size,
    seed,
    protectedRects = [],
    excludedRects = [],
    card = true,
  ) {
    const holes = [];
    for (const cell of this.fragmentCells(rect, size, seed)) {
      const { cx, cy, vertices, bounds } = cell;
      const x = cx / size;
      const y = cy / size;
      // Clustered erosion with the original irregular fragment boundaries.
      const threshold =
        0.04 +
        0.88 *
          (noise(x / 7, y / 7, seed) * 0.65 +
            noise(x / 2.6, y / 2.6, seed) * 0.2 +
            random(x, y, seed + 6) * 0.15);
      const edgeDistance = Math.max(
        0,
        Math.min(cx, cy, rect.width - cx, rect.height - cy),
      );
      const overlaps = (safe) =>
        bounds.left < safe.right &&
        bounds.right > safe.left &&
        bounds.top < safe.bottom &&
        bounds.bottom > safe.top;
      if (excludedRects.some(overlaps)) continue;
      const protectedContent = protectedRects.some(overlaps);
      const imageContent = protectedRects.some(
        (area) => area.kind === "image" && overlaps(area),
      );
      const textContent = protectedRects.some(
        (area) => area.kind === "text" && overlaps(area),
      );
      // Stable cells and thresholds make every phase additive: advancing the
      // damage never repairs a fragment or swaps to a different pattern.
      const edgeThreshold = card
        ? 0.3 * (edgeDistance / 32 + random(x, y, seed + 9) * 0.45)
        : 1;
      const backgroundThreshold =
        0.3 +
        0.23 *
          (clamp(
            edgeDistance / Math.max(1, Math.min(rect.width, rect.height) / 2),
          ) *
            0.55 +
            threshold * 0.45);
      // Warp a continuous field instead of quantizing neighboring cells
      // into rectangular blocks. Fracture fronts can curl in any direction.
      const warpedX = x / 3.5 + noise(x / 10, y / 10, seed + 13) * 3;
      const warpedY = y / 3.5 + noise(x / 10, y / 10, seed + 14) * 3;
      const organic = clamp((noise(warpedX, warpedY, seed + 11) - 0.2) / 0.6);
      const collapse = organic * 0.85 + random(x, y, seed + 12) * 0.15;
      const imageThreshold = 0.6 + 0.15 * collapse;
      const textThreshold = 0.82 + 0.11 * collapse;
      // Text drawn over an image survives with its backing until the last
      // stage; image-only links and icons can dissolve before their controls.
      const start = textContent
        ? textThreshold
        : imageContent
          ? imageThreshold
          : protectedContent
            ? textThreshold
            : Math.min(edgeThreshold, backgroundThreshold);
      let erosion = clamp((this.level - start) / 0.07);
      erosion *= 1 - this.repairStrength(cell, rect);
      if (!erosion) continue;
      const polygon = vertices.map(
        ([px, py]) =>
          `${(cx + (px - cx) * erosion).toFixed(1)},${(cy + (py - cy) * erosion).toFixed(1)}`,
      );
      holes.push(`M${polygon.join("L")}Z`);
      const viewportX = cx + rect.left;
      const viewportY = cy + rect.top;
      if (
        erosion < 1 &&
        cx > 0 &&
        cx < rect.width &&
        cy > 0 &&
        cy < rect.height &&
        viewportX > 0 &&
        viewportX < this.width &&
        viewportY > 0 &&
        viewportY < this.height
      )
        this.fringe.push({ x: viewportX, y: viewportY });
    }
    // The outer contour plus non-overlapping holes uses the even-odd fill rule.
    return `M-50000,-50000H50000V50000H-50000Z${holes.join("")}`;
  }

  repairStrength(cell, rect) {
    if (this.simulation?.cursorRepair === false) return 0;
    const distance = this.pointer
      ? Math.hypot(
          cell.cx + rect.left - this.pointer.x,
          cell.cy + rect.top - this.pointer.y,
        )
      : Infinity;
    const falloff = clamp(
      (this.repairRadius - distance) / (this.repairRadius * 0.38),
    );
    const nearby = falloff * falloff * (3 - 2 * falloff);
    const elapsed = Math.max(
      0,
      this.repairTime - (cell.repairTime ?? this.repairTime),
    );
    const lingering = this.reducedMotion.matches
      ? 0
      : (cell.repair || 0) * Math.exp(-elapsed / 350);
    cell.repair = Math.max(nearby, lingering);
    if (cell.repair < 0.005) cell.repair = 0;
    cell.repairTime = this.repairTime;
    if (cell.repair > nearby) this.repairActive = true;
    return cell.repair;
  }

  emitAmbientDust(dt) {
    if (
      !this.particlesEnabledValue ||
      this.simulation?.particles === false ||
      !this.level ||
      this.reducedMotion.matches
    )
      return;
    // Fractional particles accumulate, so even 1% emits a gentle trickle.
    // The rate is per second, independent of the display's refresh rate.
    this.dustBudget = (this.dustBudget || 0) + dt * this.level * 45;
    const count = Math.floor(this.dustBudget);
    this.dustBudget -= count;
    this.emitDust(count);
  }

  emitDust(count) {
    if (
      !this.particlesEnabledValue ||
      this.simulation?.particles === false ||
      this.reducedMotion.matches
    )
      return;
    if (!this.fringe?.length && !this.dustBounds?.length) return;
    for (let i = 0; i < count && this.particles.length < 180; i++) {
      let source = this.fringe[Math.floor(Math.random() * this.fringe.length)];
      if (!source) {
        // When no fragment is mid-break (including total decay), let residual
        // dust drift from the visible surfaces instead of stopping abruptly.
        const bounds =
          this.dustBounds[Math.floor(Math.random() * this.dustBounds.length)];
        source = {
          x: bounds.left + Math.random() * (bounds.right - bounds.left),
          y: bounds.top + Math.random() * (bounds.bottom - bounds.top),
        };
      }
      this.particles.push({
        x: source.x,
        y: source.y,
        vx: 15 + Math.random() * 35,
        vy: -12 - Math.random() * 25,
        size: 1 + Math.random() ** 1.5 * 3,
        angle: Math.random() * Math.PI,
        spin: Math.random() * 3 - 1.5,
        age: 0,
        life: 1.5 + Math.random(),
        color: this.particleColor,
      });
    }
  }

  draw(dt) {
    const ctx = this.canvasContext;
    ctx.clearRect(0, 0, this.width, this.height);
    if (
      !this.particlesEnabledValue ||
      this.simulation?.particles === false ||
      !this.level ||
      this.reducedMotion.matches
    )
      return;
    this.particles = this.particles.filter((p) => p.age < p.life);
    for (const p of this.particles) {
      p.age += dt;
      // Released fragments drift away, without an attractor or vortex.
      p.vx += 8 * dt;
      p.vy -= 6 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.angle + p.age * p.spin);
      ctx.globalAlpha =
        0.55 *
        Math.min(p.age * 10, 1) *
        clamp((p.life - p.age) / (p.life * 0.65));
      ctx.fillStyle = p.color;
      const scale = p.size * (1 - (p.age / p.life) * 0.45);
      ctx.fillRect(-scale / 2, -scale / 2, scale, scale * 0.65);
      ctx.restore();
    }
  }

  reset() {
    cancelAnimationFrame(this.frame);
    this.frame = null;
    this.lastTime = null;
    this.level = 0;
    this.requested = 0;
    this.particles = [];
    this.fringe = [];
    this.dustBounds = [];
    this.dustBudget = 0;
    this.pointer = null;
    this.repairActive = false;
    this.repairDirty = false;
    for (const [element, surface] of this.surfaces) {
      if (surface.original)
        element.style.setProperty(
          "clip-path",
          surface.original,
          surface.priority,
        );
      else element.style.removeProperty("clip-path");
      surface.clip.remove();
      surface.textClip?.remove();
      surface.textCopy?.remove();
    }
    this.surfaceResize?.disconnect();
    this.surfaces.clear();
    this.fragmentMeshes?.clear();
    this.canvasContext.clearRect(0, 0, this.width, this.height);
    this.textTarget.replaceChildren();
  }
}
