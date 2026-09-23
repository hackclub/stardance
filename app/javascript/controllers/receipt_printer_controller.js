import { Controller } from "@hotwired/stimulus";
import { playPrinterSound, primeAudio } from "../lib/printer_sound";

// Little three.js point-of-sale terminal for the Receipt promo in the discover
// rail, trimmed down from receipt.hackclub.com's <pos-terminal>. It prints a
// seeded 1-bit sketch on a paper strip, then reprints on a loop while visible.
// Loop prints are silent; pressing the printer plays the synthesised printer
// sound (browsers only allow audio after a gesture anyway).
//
// three.js is ~600KB, so it's pulled from jsDelivr only once the card is on
// screen rather than bundled into application.js for every page. The URLs are
// held in variables so esbuild leaves the dynamic imports alone.
const THREE_URL = "https://cdn.jsdelivr.net/npm/three@0.186.0/+esm";
const ROUNDED_BOX_URL =
  "https://cdn.jsdelivr.net/npm/three@0.186.0/examples/jsm/geometries/RoundedBoxGeometry.js/+esm";

const PAPER_SEGMENTS = 28;
const PAPER_LENGTH = 4.65;
const REPRINT_EVERY_MS = 6500;
const PRINT_DURATION_S = 1.93;

export default class extends Controller {
  static targets = ["canvas"];

  connect() {
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.visible = false;
    this.booting = false;
    this.disposed = false;
    this.seed = 41;
    this.onVisibility = () => this.syncLoop();
    document.addEventListener("visibilitychange", this.onVisibility);

    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting;
        if (this.visible && !this.booting) this.boot();
        this.syncLoop();
      },
      { rootMargin: "120px" },
    );
    this.observer.observe(this.element);
  }

  disconnect() {
    this.observer?.disconnect();
    document.removeEventListener("visibilitychange", this.onVisibility);
    clearTimeout(this.reprintTimer);
    cancelAnimationFrame(this.frame);
    this.disposed = true;
    if (this.renderer) {
      this.scene.traverse((obj) => {
        obj.geometry?.dispose();
        obj.material?.map?.dispose();
        obj.material?.dispose();
      });
      this.renderer.dispose();
      this.renderer.forceContextLoss();
      this.renderer = null;
    }
  }

  async boot() {
    this.booting = true;
    let THREE, RoundedBoxGeometry;
    try {
      [THREE, { RoundedBoxGeometry }] = await Promise.all([
        import(THREE_URL),
        import(ROUNDED_BOX_URL),
      ]);
    } catch {
      this.drawFallback();
      return;
    }
    if (this.disposed) return;

    this.THREE = THREE;
    this.paperCanvas = Object.assign(document.createElement("canvas"), {
      width: 384,
      height: 540,
    });
    this.screenCanvas = Object.assign(document.createElement("canvas"), {
      width: 300,
      height: 450,
    });
    drawReceiptArt(this.paperCanvas, this.seed);

    try {
      this.buildScene(RoundedBoxGeometry);
    } catch {
      this.drawFallback();
      return;
    }

    this.canvasTarget.addEventListener("pointermove", (e) => this.tilt(e));
    this.canvasTarget.addEventListener("pointerleave", () => this.tilt(null));

    if (this.reduceMotion) {
      this.progress = 1;
      this.updatePaper();
      this.drawScreen("click me uwu", 1);
      this.renderOnce();
    } else {
      this.print();
      // Paint a first frame even if the tab is backgrounded, so the card
      // never shows an empty stage.
      this.renderOnce();
    }
    this.syncLoop();
  }

  buildScene(RoundedBoxGeometry) {
    const THREE = this.THREE;
    const renderer = new THREE.WebGLRenderer({
      canvas: this.canvasTarget,
      alpha: true,
      antialias: true,
    });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100);
    camera.position.set(0, 0.5, 18);

    scene.add(new THREE.HemisphereLight(0xffffff, 0x6f665c, 2.5));
    const key = new THREE.DirectionalLight(0xffffff, 4.2);
    key.position.set(-4, 7, 8);
    key.castShadow = true;
    scene.add(key);
    const rim = new THREE.DirectionalLight(0xff8c78, 2.2);
    rim.position.set(6, 1, 3);
    scene.add(rim);

    const terminal = new THREE.Group();
    terminal.position.y = -0.65;
    terminal.rotation.set(-0.04, -0.18, -0.035);
    scene.add(terminal);

    const cream = new THREE.MeshPhysicalMaterial({
      color: 0xf3eee3,
      roughness: 0.5,
      clearcoat: 0.16,
    });
    const red = new THREE.MeshPhysicalMaterial({
      color: 0xec4e3d,
      roughness: 0.42,
      clearcoat: 0.25,
    });
    const dark = new THREE.MeshStandardMaterial({
      color: 0x151515,
      roughness: 0.35,
    });
    const box = (w, h, d, r, mat, x, y, z) => {
      const mesh = new THREE.Mesh(new RoundedBoxGeometry(w, h, d, 8, r), mat);
      mesh.position.set(x, y, z);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      terminal.add(mesh);
      return mesh;
    };

    box(4.2, 6.2, 1.15, 0.34, cream, 0, -0.4, 0);
    box(4.24, 1.72, 1.28, 0.38, red, 0, 2.55, 0.02);
    box(3.58, 4.45, 0.16, 0.18, dark, 0, -0.58, 0.64);
    box(3.35, 0.13, 0.16, 0.04, dark, 0, 1.76, 0.7).castShadow = false;
    box(0.22, 0.82, 0.24, 0.1, red, 2.12, 0.25, 0.25);

    this.screenTexture = new THREE.CanvasTexture(this.screenCanvas);
    this.screenTexture.colorSpace = THREE.SRGBColorSpace;
    const screen = new THREE.Mesh(
      new THREE.PlaneGeometry(3.18, 4.05),
      new THREE.MeshBasicMaterial({ map: this.screenTexture }),
    );
    screen.position.set(0, -0.58, 0.735);
    terminal.add(screen);

    this.paperTexture = new THREE.CanvasTexture(this.paperCanvas);
    this.paperTexture.colorSpace = THREE.SRGBColorSpace;
    this.paperTexture.anisotropy = renderer.capabilities.getMaxAnisotropy();

    const rows = PAPER_SEGMENTS + 1;
    const geo = new THREE.BufferGeometry();
    const uvs = new Float32Array(rows * 4);
    const indices = [];
    for (let row = 0; row < rows; row++) {
      const t = row / PAPER_SEGMENTS;
      uvs.set([0, t, 1, t], row * 4);
      const v = row * 2;
      if (row < PAPER_SEGMENTS) indices.push(v, v + 1, v + 3, v, v + 3, v + 2);
    }
    geo.setAttribute(
      "position",
      new THREE.BufferAttribute(new Float32Array(rows * 6), 3),
    );
    geo.setAttribute("uv", new THREE.BufferAttribute(uvs, 2));
    geo.setIndex(indices);
    const paper = new THREE.Mesh(
      geo,
      new THREE.MeshStandardMaterial({
        map: this.paperTexture,
        roughness: 0.92,
        side: THREE.DoubleSide,
      }),
    );
    paper.castShadow = true;
    terminal.add(paper);

    Object.assign(this, { renderer, scene, camera, terminal, paperGeo: geo });
    this.rotX = this.targetX = -0.04;
    this.rotY = this.targetY = -0.18;
    this.progress = 0.025;
    this.updatePaper();
    this.drawScreen("click me uwu", 0);
  }

  async press(event) {
    event.preventDefault();
    if (!this.renderer || this.printStartedAt) return;
    const audible = await primeAudio();
    this.print({ sound: audible });
  }

  print({ sound = false } = {}) {
    if (!this.renderer || this.printStartedAt) return;
    this.seed = 1 + Math.floor(Math.random() * 998);
    drawReceiptArt(this.paperCanvas, this.seed);
    this.paperTexture.needsUpdate = true;
    this.progress = 0.025;
    this.updatePaper();

    if (this.reduceMotion) {
      this.progress = 1;
      this.updatePaper();
      this.drawScreen("click me uwu", 1);
      this.renderOnce();
      return;
    }
    if (sound) playPrinterSound({ duration: PRINT_DURATION_S });
    this.printStartedAt = performance.now();
    this.scheduleReprint();
  }

  scheduleReprint() {
    clearTimeout(this.reprintTimer);
    if (this.reduceMotion) return;
    this.reprintTimer = setTimeout(() => {
      if (this.running) this.print();
      else this.pendingReprint = true;
    }, REPRINT_EVERY_MS);
  }

  tilt(e) {
    if (this.reduceMotion) return;
    if (!e) {
      this.targetX = -0.04;
      this.targetY = -0.18;
      return;
    }
    const r = this.canvasTarget.getBoundingClientRect();
    const x = ((e.clientX - r.left) / r.width) * 2 - 1;
    const y = ((e.clientY - r.top) / r.height) * 2 - 1;
    this.targetY = -0.18 + x * 0.1;
    this.targetX = -0.04 - y * 0.05;
  }

  // Only spin the render loop while the card is on screen and the tab is
  // focused; the rail sits on every home pageload.
  syncLoop() {
    const shouldRun =
      this.renderer && !this.reduceMotion && this.visible && !document.hidden;
    if (shouldRun && !this.running) {
      this.running = true;
      if (this.pendingReprint) {
        this.pendingReprint = false;
        this.print();
      }
      this.frame = requestAnimationFrame((t) => this.tick(t));
    } else if (!shouldRun && this.running) {
      this.running = false;
      cancelAnimationFrame(this.frame);
    }
  }

  tick(time) {
    if (!this.running || !this.renderer) return;
    this.rotX += (this.targetX - this.rotX) * 0.06;
    this.rotY += (this.targetY - this.rotY) * 0.06;
    this.terminal.rotation.x = this.rotX;
    this.terminal.rotation.y = this.rotY;

    if (this.printStartedAt) {
      const elapsed = time - this.printStartedAt;
      const transfer = Math.min(1, elapsed / 750);
      const eased =
        1 - Math.pow(1 - Math.min(1, Math.max(0, elapsed - 480) / 1450), 3);
      this.progress = 0.025 + eased * 0.975;
      this.updatePaper();
      this.drawScreen(eased < 1 ? "PRINTING…" : "click me uwu", transfer);
      if (eased >= 1) this.printStartedAt = 0;
    }

    this.renderOnce();
    this.frame = requestAnimationFrame((t) => this.tick(t));
  }

  renderOnce() {
    this.resize();
    this.renderer.render(this.scene, this.camera);
  }

  resize() {
    const w = Math.max(1, this.canvasTarget.clientWidth);
    const h = Math.max(1, this.canvasTarget.clientHeight);
    const ratio = this.renderer.getPixelRatio();
    if (
      this.canvasTarget.width === Math.floor(w * ratio) &&
      this.canvasTarget.height === Math.floor(h * ratio)
    )
      return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    const fitZ =
      9.4 / (2 * Math.tan((Math.PI / 180) * 20)) / Math.min(1, w / h / 0.82);
    this.camera.position.z = Math.max(13, fitZ);
    this.camera.updateProjectionMatrix();
  }

  updatePaper() {
    const length = PAPER_LENGTH * this.progress;
    const pos = this.paperGeo.attributes.position;
    const uv = this.paperGeo.attributes.uv;
    for (let row = 0; row <= PAPER_SEGMENTS; row++) {
      const t = row / PAPER_SEGMENTS;
      const y = 1.82 + t * length;
      const z = 0.79 + Math.sin(t * Math.PI * 0.55) * 0.28 * this.progress;
      const v = row * 2;
      pos.setXYZ(v, -1.48, y, z);
      pos.setXYZ(v + 1, 1.48, y, z);
      uv.setY(v, 1 - this.progress + t * this.progress);
      uv.setY(v + 1, 1 - this.progress + t * this.progress);
    }
    pos.needsUpdate = true;
    uv.needsUpdate = true;
    this.paperGeo.computeVertexNormals();
  }

  drawScreen(status, transfer) {
    const ctx = this.screenCanvas.getContext("2d");
    const { width: w, height: h } = this.screenCanvas;
    ctx.fillStyle = "#111318";
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = "#ec3750";
    ctx.fillRect(0, 0, w, 42);
    ctx.fillStyle = "#fff";
    ctx.font = "700 14px ui-monospace, Consolas, monospace";
    ctx.textAlign = "left";
    ctx.fillText("RECEIPT!", 16, 27);
    ctx.textAlign = "right";
    ctx.fillText(`NO. ${String(this.seed).padStart(3, "0")}`, w - 16, 27);

    ctx.save();
    ctx.beginPath();
    ctx.rect(14, 56, w - 28, 326);
    ctx.clip();
    ctx.fillStyle = "#252932";
    ctx.fillRect(14, 56, w - 28, 326);
    // The preview slides up and out of the screen as it "transfers" to paper.
    if (transfer < 1)
      ctx.drawImage(this.paperCanvas, 43, 64 - transfer * 345, 214, 301);
    else {
      ctx.fillStyle = "#fffdf3";
      ctx.font = "700 20px ui-monospace, Consolas, monospace";
      ctx.textAlign = "center";
      ctx.fillText("printed!", w / 2, 205);
      ctx.fillStyle = "#8a93a3";
      ctx.font = "700 13px ui-monospace, Consolas, monospace";
      ctx.fillText("your sketch, on paper", w / 2, 234);
      ctx.fillText("↑ ↑ ↑", w / 2, 262);
    }
    ctx.restore();

    ctx.fillStyle = "#ec3750";
    ctx.fillRect(36, 396, w - 72, 36);
    ctx.fillStyle = "#fff";
    ctx.font = "700 13px ui-monospace, Consolas, monospace";
    ctx.textAlign = "center";
    ctx.fillText(status, w / 2, 419);
    this.screenTexture.needsUpdate = true;
  }

  // No WebGL or the CDN is blocked: just show a flat receipt so the card
  // still reads.
  drawFallback() {
    const canvas = this.canvasTarget;
    const w = (canvas.width = canvas.clientWidth * 2);
    const h = (canvas.height = canvas.clientHeight * 2);
    const art = Object.assign(document.createElement("canvas"), {
      width: 384,
      height: 540,
    });
    drawReceiptArt(art, this.seed);
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const pw = w * 0.52;
    const ph = (pw * art.height) / art.width;
    ctx.save();
    ctx.translate(w / 2, h / 2);
    ctx.rotate(-0.06);
    ctx.shadowColor = "rgb(0 0 0 / 35%)";
    ctx.shadowBlur = 24;
    ctx.shadowOffsetY = 10;
    ctx.drawImage(art, -pw / 2, -ph / 2, pw, ph);
    ctx.restore();
  }
}

// --- Seeded 1-bit receipt art, a compact cut of receipt.hackclub.com's plotters ---

function rng(seed) {
  let v = seed >>> 0 || 1;
  return () => {
    v = (v * 1664525 + 1013904223) >>> 0;
    return v / 4294967296;
  };
}

function valueNoise(rand) {
  const p = new Float32Array(512).map(() => rand());
  const fade = (t) => t * t * (3 - 2 * t);
  const g = (a, b) => p[((a & 31) + ((b & 15) << 5)) & 511];
  return (x, y) => {
    const xi = Math.floor(x);
    const yi = Math.floor(y);
    const xf = fade(x - xi);
    const yf = fade(y - yi);
    const top = g(xi, yi) + (g(xi + 1, yi) - g(xi, yi)) * xf;
    const bot = g(xi, yi + 1) + (g(xi + 1, yi + 1) - g(xi, yi + 1)) * xf;
    return top + (bot - top) * yf;
  };
}

const PLOTTERS = {
  ridges(ctx, box, rand) {
    const noise = valueNoise(rand);
    const left = box.x + box.w * 0.06;
    const right = box.x + box.w * 0.94;
    for (let layer = 0; layer < 6; layer++) {
      ctx.fillStyle = layer % 2 === 0 ? "#151515" : "#fffdf3";
      ctx.lineWidth = 2;
      ctx.beginPath();
      const top = box.y + box.h * 0.12 + (layer * box.h * 0.62) / 6;
      ctx.moveTo(left, box.y + box.h);
      for (let x = left; x <= right; x += 4)
        ctx.lineTo(x, top - noise(x * 0.012, layer * 4.2) * box.h * 0.16);
      ctx.lineTo(right, box.y + box.h);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }
  },
  orbit(ctx, box, rand) {
    const cx = box.x + box.w / 2;
    const cy = box.y + box.h / 2;
    const R = Math.min(box.w, box.h) * 0.46;
    const arms = 3 + Math.floor(rand() * 4);
    ctx.lineWidth = 1.4;
    for (let a = 0; a < arms; a++) {
      const rot = (Math.PI * a) / arms + rand() * 0.4;
      const ry = R * (0.18 + rand() * 0.55);
      for (let k = 0; k < 9; k++) {
        ctx.beginPath();
        ctx.ellipse(
          cx,
          cy,
          R * (0.35 + k * 0.07),
          ry,
          rot + (k * Math.PI) / 26,
          0,
          Math.PI * 2,
        );
        ctx.stroke();
      }
    }
    ctx.beginPath();
    ctx.arc(cx, cy, R * 0.07, 0, Math.PI * 2);
    ctx.fill();
  },
  halftone(ctx, box, rand) {
    const noise = valueNoise(rand);
    const cell = Math.max(6, box.w / 30);
    for (let y = box.y; y < box.y + box.h; y += cell) {
      for (let x = box.x; x < box.x + box.w; x += cell) {
        const r =
          (cell / 2) *
          Math.min(1, Math.max(0, noise(x * 0.02, y * 0.02) * 1.5));
        if (r < 0.4) continue;
        ctx.beginPath();
        ctx.arc(x + cell / 2, y + cell / 2, r, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  },
  starburst(ctx, box, rand) {
    const cx = box.x + box.w / 2;
    const cy = box.y + box.h / 2;
    const R = Math.min(box.w, box.h) * 0.46;
    ctx.lineCap = "round";
    for (let i = 0; i < 34; i++) {
      const a = (Math.PI * 2 * i) / 34 + rand() * 0.08;
      const inner = R * (0.27 + rand() * 0.18);
      const outer = R * (0.72 + rand() * 0.35);
      ctx.lineWidth = 1.5 + rand() * 3;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner);
      ctx.lineTo(cx + Math.cos(a) * outer, cy + Math.sin(a) * outer);
      ctx.stroke();
    }
    ctx.beginPath();
    ctx.arc(cx, cy, R * 0.1, 0, Math.PI * 2);
    ctx.fill();
  },
};
const PLOTTER_NAMES = Object.keys(PLOTTERS);

function drawReceiptArt(canvas, seed) {
  const ctx = canvas.getContext("2d");
  const { width: w, height: h } = canvas;
  const rand = rng(seed * 2654435761);
  const pad = w * 0.06;
  const ink = "#151515";

  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.setLineDash([]);
  ctx.fillStyle = "#fffdf3";
  ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = ink;
  ctx.strokeStyle = ink;
  ctx.lineJoin = "round";

  const headH = h * 0.1;
  const footH = h * 0.16;
  ctx.font = `700 ${w * 0.045}px ui-monospace, Consolas, monospace`;
  ctx.textAlign = "left";
  ctx.fillText("RECEIPT!", pad, headH * 0.62);
  ctx.textAlign = "right";
  ctx.fillText(
    `NO. ${String(seed % 1000).padStart(3, "0")}`,
    w - pad,
    headH * 0.62,
  );
  ctx.setLineDash([w * 0.02, w * 0.016]);
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(pad, headH * 0.86);
  ctx.lineTo(w - pad, headH * 0.86);
  ctx.stroke();
  ctx.setLineDash([]);

  const style = PLOTTER_NAMES[Math.floor(rand() * PLOTTER_NAMES.length)];
  ctx.save();
  PLOTTERS[style](
    ctx,
    {
      x: pad * 0.6,
      y: headH + h * 0.02,
      w: w - pad * 1.2,
      h: h - headH - footH - h * 0.04,
    },
    rand,
  );
  ctx.restore();

  ctx.fillStyle = ink;
  ctx.font = `700 ${w * 0.044}px ui-monospace, Consolas, monospace`;
  ctx.textAlign = "center";
  ctx.fillText("HACK CLUB", w / 2, h - footH * 0.52);
  for (let x = pad * 1.4; x < w - pad * 1.4;) {
    const bar = 1 + Math.floor(rand() * 3);
    ctx.fillRect(x, h - footH * 0.36, bar * 1.5, footH * 0.26);
    x += bar * 1.5 + 1.5 + Math.floor(rand() * 3) * 1.5;
  }

  // Thermal noise: faded print-head streaks and speckle so it reads as a real
  // cheap receipt rather than a clean vector.
  const img = ctx.getImageData(0, 0, w, h);
  const d = img.data;
  const streaks = new Float32Array(w).map(() =>
    rand() > 0.965 ? 0.35 + rand() * 0.4 : 0,
  );
  for (let i = 0; i < d.length; i += 4) {
    const x = (i / 4) % w;
    const inked = d[i] < 128;
    const r = Math.random();
    let v = d[i];
    if (inked && (r < 0.06 || Math.random() < streaks[x])) v = 200 + r * 55;
    else if (!inked && r < 0.012) v = 40 + r * 60;
    const grain = (Math.random() - 0.5) * 18;
    d[i] = clamp(v + grain);
    d[i + 1] = clamp(v + grain - 1);
    d[i + 2] = clamp(v + grain - (inked ? 0 : 10));
  }
  ctx.putImageData(img, 0, 0);
}

function clamp(v) {
  return v < 0 ? 0 : v > 255 ? 255 : v;
}
