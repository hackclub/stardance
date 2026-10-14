// The sparks thrown up by the Forge card's fire, drawn additively on a 2D
// canvas. Each spark cools from core to flame to ember as it rises and twinkles
// as it goes; sizes and speeds are in canvas pixels.
const SPRITE_SIZE = 32;
const STAGES = ["core", "flame", "ember"];

export default class Sparks {
  constructor(canvas, colors) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.sprites = STAGES.map((stage) => buildSprite(colors[stage]));
    this.particles = [];
  }

  resize(width, height) {
    this.canvas.width = width;
    this.canvas.height = height;
  }

  emit({ x, y, vx = 0, vy = 0, size, life, lift = 0 }) {
    this.particles.push({
      x,
      y,
      vx,
      vy,
      size,
      life,
      lift,
      age: 0,
      seed: Math.random() * 1000,
    });
  }

  step(dt) {
    const drag = Math.exp(-dt * 1.8);
    this.particles = this.particles.filter((p) => {
      p.age += dt;
      if (p.age >= p.life) return false;
      p.vy -= p.lift * dt;
      p.vx *= drag;
      p.vy *= drag;
      // Sparks drift side to side on the rising heat.
      p.x += (p.vx + Math.sin(p.seed + p.age * 5) * p.size * 6) * dt;
      p.y += p.vy * dt;
      return true;
    });
  }

  // `underlay` paints beneath the sparks each frame, after the canvas is cleared.
  draw(underlay) {
    const { ctx, canvas } = this;
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    underlay?.(ctx);
    ctx.globalCompositeOperation = "lighter";
    for (const p of this.particles) {
      const t = p.age / p.life;
      // Each spark cools at its own pace, so neighbours never share a colour.
      const heat = t + (p.seed % 1) * 0.2;
      const stage = heat < 0.2 ? 0 : heat < 0.55 ? 1 : 2;
      const size = p.size * (1 - t * 0.5) * 2;
      const twinkle = 0.6 + 0.4 * Math.sin(p.seed + p.age * 30);
      ctx.globalAlpha = Math.min(1, t * 10) * (1 - t) ** 1.5 * twinkle;
      ctx.drawImage(
        this.sprites[stage],
        p.x - size / 2,
        p.y - size / 2,
        size,
        size,
      );
    }
  }
}

function buildSprite(color) {
  const sprite = document.createElement("canvas");
  sprite.width = sprite.height = SPRITE_SIZE;
  const ctx = sprite.getContext("2d");
  const half = SPRITE_SIZE / 2;
  const glow = ctx.createRadialGradient(half, half, 0, half, half, half);
  glow.addColorStop(0, color);
  glow.addColorStop(1, "transparent");
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, SPRITE_SIZE, SPRITE_SIZE);
  return sprite;
}
