const TAU = Math.PI * 2;
const PARTICLES = 700;
const GLINTS = 14;
const TONE_ALPHA = { deep: 0.08, mid: 0.06, hi: 0.05 };

const rand = (min, max) => min + Math.random() * (max - min);
const gauss = () => (Math.random() + Math.random() + Math.random() - 1.5) / 1.5;

// 2D canvas fallback for ShaderRing: soft sprites orbit and leave fading trails in an
// offscreen buffer, with crisp glints drawn over it each frame.
export default class SmokeRing {
  constructor(canvas) {
    this.ctx = canvas.getContext("2d");
    this.trails = document.createElement("canvas");
    this.trailsCtx = this.trails.getContext("2d");
    this.particles = Array.from({ length: PARTICLES }, () => {
      const wisp = Math.random() < 0.15;
      const off = wisp ? rand(0.15, 0.35) * Math.sign(gauss()) : gauss() * 0.1;
      const roll = Math.random();
      const tone = roll < 0.45 ? "deep" : roll < 0.85 ? "mid" : "hi";
      return {
        angle: rand(0, TAU),
        off,
        speed: rand(0.5, 0.8) * (1 - off * 1.5),
        phase: rand(0, TAU),
        size: tone === "hi" ? rand(0.025, 0.05) : rand(0.04, 0.09),
        alpha: (wisp ? 0.5 : 1) * TONE_ALPHA[tone],
        tone,
      };
    });
    this.glints = Array.from({ length: GLINTS }, () => ({
      angle: rand(0, TAU),
      off: gauss() * 0.1,
      phase: rand(0, TAU),
      rate: rand(1, 3.5),
    }));
  }

  resize(size) {
    this.ctx.canvas.width = this.ctx.canvas.height = size;
    this.trails.width = this.trails.height = size;
    this.size = size;
  }

  setColors(colors) {
    this.sprites = Object.fromEntries(
      Object.entries(colors).map(([name, rgb]) => [name, makeSprite(rgb)]),
    );
  }

  // The hole is the flat image underneath, so there is nothing to hand over.
  setDestination() {}
  openHole() {}
  closeHole() {}

  draw({ time, step, dt, surge }) {
    const { ctx, trailsCtx, size } = this;
    const center = size / 2;
    const radius = size * 0.33 * (1 + surge * 0.15);

    trailsCtx.globalCompositeOperation = "destination-out";
    trailsCtx.globalAlpha = 1;
    trailsCtx.fillStyle = `rgba(0, 0, 0, ${1 - Math.pow(0.85, dt * 60)})`;
    trailsCtx.fillRect(0, 0, size, size);
    trailsCtx.globalCompositeOperation = "lighter";
    for (const p of this.particles) {
      p.angle += step * p.speed;
      const wobble =
        Math.sin(p.angle * 3 + time * 0.6 + p.phase) * 0.06 +
        Math.sin(p.angle * 5 - time * 0.9 + p.phase * 2) * 0.03;
      const r = radius * (1 + p.off + wobble);
      const s = size * p.size;
      trailsCtx.globalAlpha = p.alpha;
      trailsCtx.drawImage(
        this.sprites[p.tone],
        center + Math.cos(p.angle) * r - s / 2,
        center + Math.sin(p.angle) * r - s / 2,
        s,
        s,
      );
    }

    ctx.clearRect(0, 0, size, size);
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;
    ctx.drawImage(this.trails, 0, 0);
    ctx.globalCompositeOperation = "lighter";
    for (const g of this.glints) {
      g.angle += step * 0.5;
      const r = radius * (1 + g.off);
      const twinkle = Math.pow(
        0.5 + 0.5 * Math.sin(time * g.rate + g.phase),
        3,
      );
      this.drawGlint(
        center + Math.cos(g.angle) * r,
        center + Math.sin(g.angle) * r,
        size * 0.045 * (0.4 + twinkle),
        0.25 + 0.75 * twinkle,
      );
    }
  }

  drawGlint(x, y, length, alpha) {
    const { ctx, size } = this;
    const sprite = this.sprites.glint;
    const thickness = size * 0.008;
    ctx.globalAlpha = alpha;
    ctx.drawImage(sprite, x - length, y - thickness / 2, length * 2, thickness);
    ctx.drawImage(sprite, x - thickness / 2, y - length, thickness, length * 2);
    ctx.drawImage(
      sprite,
      x - length * 0.35,
      y - length * 0.35,
      length * 0.7,
      length * 0.7,
    );
  }

  destroy() {}
}

function makeSprite([r, g, b], size = 64) {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext("2d");
  const rgb = [r, g, b].map((channel) => Math.round(channel * 255)).join(", ");
  const gradient = ctx.createRadialGradient(
    size / 2,
    size / 2,
    0,
    size / 2,
    size / 2,
    size / 2,
  );
  gradient.addColorStop(0, `rgba(${rgb}, 1)`);
  gradient.addColorStop(0.3, `rgba(${rgb}, 0.45)`);
  gradient.addColorStop(1, `rgba(${rgb}, 0)`);
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  return canvas;
}
