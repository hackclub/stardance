import { Controller } from "@hotwired/stimulus";

// Crescent's landing sky (hackclub/crescent, components/landing/shader.ts),
// cut down to the card: the quantised light the hand sits in, cloud pushed
// out into the edges, stars, and the arcs turning round the light. The rock,
// the bake flags and the scroll parallax stay behind; the clouds drift on the
// clock instead.

const PALETTE = [
  "void",
  "deep",
  "mid",
  "violet",
  "magenta",
  "pink",
  "hot",
  "spark",
];
const MAX_DPR = 2;
const MIN_SCALE = 0.5;
const FRAME_BUDGET_MS = 1000 / 30;
const QUALITY_WINDOW_MS = 2000;
const DRIFT_PER_S = 0.008;
const POINTER_EASE = 2.7;
const STILL_TIME_S = 20;

const VERTEX_SHADER = `#version 300 es
in vec2 a;
void main() { gl_Position = vec4(a, 0.0, 1.0); }`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;

uniform vec2  u_res;
uniform vec2  u_light;   // the light's centre, in canvas pixels
uniform vec2  u_mouse;   // chased pointer, -1 to 1 across the card
uniform float u_time;
uniform float u_drift;   // card-heights the weather has moved
uniform vec3  u_${PALETTE.join(", u_")};

out vec4 fragColor;

const vec2 SEED = vec2(41.7, 13.2);

float hash12(vec2 p) {
  vec3 p3 = fract(p.xyx * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
             mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
  p += SEED;
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(11.0, 7.0); a *= 0.5; }
  return v;
}

// A shape edge about a pixel wide wherever it lands, not a gradient.
float hard(float v, float edge) {
  float w = max(fwidth(v) * 0.70, 1e-5);
  return smoothstep(edge - w, edge + w, v);
}

// Three arcs turning about the light, each on its own clock.
vec3 arcs(vec3 col, vec2 q, float t) {
  float r = length(q);
  float ang = atan(q.y, q.x);
  for (int k = 0; k < 3; k++) {
    float fk = float(k);
    float arc = smoothstep(0.0028, 0.0, abs(r - (0.235 + fk * 0.082)));
    float a01 = fract((ang + t * (0.020 + fk * 0.012) + fk * 2.1) / 6.28318);
    float span = 0.30 + 0.12 * fk;
    arc *= smoothstep(0.0, 0.06, a01) * smoothstep(span, span - 0.09, a01);
    col += u_spark * arc * 0.34;
  }
  return col;
}

void main() {
  float R = u_res.y;
  vec2 p = (gl_FragCoord.xy - 0.5 * u_res) / R;
  vec2 fp = (gl_FragCoord.xy - u_light) / R;
  float rf = length(fp);
  float t = u_time;

  // The light, as a field quantised into flat painted steps.
  float lum = exp(-rf * 3.80) * 0.95;
  lum += (0.5 + 0.5 * sin(6.28318 * (-fp.y / 2.0))) * 0.30;
  lum += (fbm(vec2(p.x * 1.9, (p.y - u_drift) * 2.4)) - 0.5) * 0.24;
  lum = floor(clamp(lum, 0.0, 1.0) * 6.0 + 0.5) / 6.0;

  vec3 col = u_void;
  col = mix(col, u_deep, step(0.20, lum));
  col = mix(col, u_mid, step(0.42, lum));
  col = mix(col, u_violet, step(0.62, lum));
  col = mix(col, u_magenta, step(0.80, lum));
  col = mix(col, u_pink, step(0.92, lum));
  col = mix(col, u_hot, step(0.99, lum));

  col = arcs(col, fp, t);

  // Stars: a fine field of points and a coarse one of four-point sparkles.
  float slowY = -u_drift * 0.16;
  vec2 sg = (vec2(p.x, p.y + slowY) + u_mouse * 0.010) * 13.0;
  vec2 sid = floor(sg);
  float sh = hash12(sid);
  vec2 sc = vec2(hash12(sid + 7.1), hash12(sid + 13.7)) * 0.7 + 0.15;
  float tw = 0.45 + 0.55 * sin(t * (0.6 + sh * 2.0) + sh * 52.0);
  float starLight = step(0.945, sh) * smoothstep(0.07, 0.0, length(fract(sg) - sc)) * tw * 0.85;

  vec2 bg = (vec2(p.x, p.y + slowY) + u_mouse * 0.014) * 4.6;
  vec2 bid = floor(bg), bf = fract(bg) - 0.5;
  float bh = hash12(bid + 3.3);
  float bs = 0.5 + 0.5 * sin(t * (0.4 + bh) + bh * 80.0);
  float ax = smoothstep(0.28, 0.0, abs(bf.x)) * smoothstep(0.030, 0.0, abs(bf.y));
  float ay = smoothstep(0.28, 0.0, abs(bf.y)) * smoothstep(0.030, 0.0, abs(bf.x));
  starLight += step(0.915, bh) * (0.30 + 0.70 * bs * bs) * (smoothstep(0.05, 0.0, length(bf)) + 0.5 * (ax + ay)) * 0.8;
  col += u_spark * starLight;

  // Cloud, denser the further from the light, so it packs into the edges and
  // leaves the hand clear whatever the noise does.
  vec2 cp = (vec2(p.x, p.y - u_drift) + u_mouse * 0.028) * 1.60;
  float dens = fbm(cp * 1.30) * 0.80;
  dens += smoothstep(0.36, 0.95, length(vec2(fp.x * 0.80, fp.y * 1.20))) * 0.58;
  float e0 = hard(dens, 0.700);
  col = mix(col, u_mid, e0);
  col = mix(col, u_deep, hard(dens, 0.790));
  col = mix(col, u_void, hard(dens, 0.890));
  col = mix(col, u_magenta, clamp(e0 - hard(dens, 0.728), 0.0, 1.0) * 0.45);

  // Dither, the only thing between flat fills and banding.
  col += (hash12(gl_FragCoord.xy + fract(t)) - 0.5) * 0.014;
  fragColor = vec4(col, 1.0);
}`;

export default class extends Controller {
  static targets = ["canvas", "light"];

  connect() {
    this.still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.time = this.still ? STILL_TIME_S : 0;
    this.target = { x: 0, y: 0 };
    this.mouse = { x: 0, y: 0 };
    this.scale = 1;
    this.visible = false;
    this.layoutDirty = true;

    this.resizeObserver = new ResizeObserver(() => {
      this.layoutDirty = true;
      if (!this.running) this.draw();
    });
    this.resizeObserver.observe(this.element);
    this.onVisibility = () => this.syncLoop();
    document.addEventListener("visibilitychange", this.onVisibility);

    this.intersectionObserver = new IntersectionObserver(([entry]) => {
      this.visible = entry.isIntersecting;
      if (this.visible && !this.gl) this.boot();
      this.syncLoop();
    });
    this.intersectionObserver.observe(this.element);
  }

  disconnect() {
    this.intersectionObserver?.disconnect();
    this.resizeObserver?.disconnect();
    document.removeEventListener("visibilitychange", this.onVisibility);
    this.running = false;
    cancelAnimationFrame(this.frame);
    this.gl?.getExtension("WEBGL_lose_context")?.loseContext();
    this.gl = null;
  }

  boot() {
    const gl = this.canvasTarget.getContext("webgl2", {
      alpha: false,
      antialias: false,
      powerPreference: "low-power",
    });
    if (!gl) return;
    const program = linkProgram(gl);
    if (!program) return;

    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 3, -1, -1, 3]),
      gl.STATIC_DRAW,
    );
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

    this.gl = gl;
    this.uniforms = Object.fromEntries(
      ["res", "light", "mouse", "time", "drift"].map((name) => [
        name,
        gl.getUniformLocation(program, `u_${name}`),
      ]),
    );
    const style = getComputedStyle(this.element);
    for (const name of PALETTE)
      gl.uniform3fv(
        gl.getUniformLocation(program, `u_${name}`),
        hexToRgb(style.getPropertyValue(`--crescent-${name}`)),
      );
    this.draw();
  }

  enter(event) {
    this.track(event);
  }

  leave() {
    this.target = { x: 0, y: 0 };
  }

  track(event) {
    const rect = this.element.getBoundingClientRect();
    this.target = {
      x: ((event.clientX - rect.left) / rect.width) * 2 - 1,
      y: 1 - ((event.clientY - rect.top) / rect.height) * 2,
    };
  }

  syncLoop() {
    const shouldRun =
      this.gl && !this.still && this.visible && !document.hidden;
    if (shouldRun && !this.running) {
      this.running = true;
      this.lastTick = null;
      this.qualityElapsed = this.qualityFrames = 0;
      this.frame = requestAnimationFrame((now) => this.tick(now));
    } else if (!shouldRun && this.running) {
      this.running = false;
      cancelAnimationFrame(this.frame);
    }
  }

  tick(now) {
    if (!this.running) return;
    this.frame = requestAnimationFrame((next) => this.tick(next));
    const elapsed = this.lastTick == null ? 0 : now - this.lastTick;
    this.lastTick = now;
    if (elapsed > 0) this.adaptQuality(elapsed);
    const dt = Math.min(0.1, elapsed / 1000);
    this.time += dt;

    // Chased rather than followed: a hard cut to the cursor reads as a glitch,
    // a lagging ease reads as depth.
    const ease = 1 - Math.exp(-dt * POINTER_EASE);
    this.mouse.x += (this.target.x - this.mouse.x) * ease;
    this.mouse.y += (this.target.y - this.mouse.y) * ease;
    this.draw();
  }

  // Sustained slowdowns drop the resolution a step; the flat fills hide it.
  adaptQuality(elapsed) {
    this.qualityElapsed += elapsed;
    this.qualityFrames++;
    if (this.qualityElapsed < QUALITY_WINDOW_MS) return;
    const average = this.qualityElapsed / this.qualityFrames;
    this.qualityElapsed = this.qualityFrames = 0;
    if (average > FRAME_BUDGET_MS * 1.35 && this.scale > MIN_SCALE) {
      this.scale = Math.max(MIN_SCALE, this.scale * 0.75);
      this.layoutDirty = true;
    }
  }

  draw() {
    const { gl, uniforms: u } = this;
    if (!gl || !this.updateLayout()) return;
    gl.uniform2f(u.mouse, this.mouse.x, this.mouse.y);
    gl.uniform1f(u.time, this.time);
    gl.uniform1f(u.drift, this.time * DRIFT_PER_S);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  updateLayout() {
    if (!this.layoutDirty) return true;
    const rect = this.canvasTarget.getBoundingClientRect();
    if (!rect.width || !rect.height) return false;
    const ratio = Math.min(window.devicePixelRatio || 1, MAX_DPR) * this.scale;
    const width = Math.max(1, Math.round(rect.width * ratio));
    const height = Math.max(1, Math.round(rect.height * ratio));
    const { gl, uniforms: u } = this;
    this.canvasTarget.width = width;
    this.canvasTarget.height = height;
    gl.viewport(0, 0, width, height);
    gl.uniform2f(u.res, width, height);

    const light = this.lightTarget.getBoundingClientRect();
    gl.uniform2f(
      u.light,
      (light.left + light.width / 2 - rect.left) * (width / rect.width),
      (rect.bottom - light.top - light.height / 2) * (height / rect.height),
    );
    this.layoutDirty = false;
    return true;
  }
}

function hexToRgb(hex) {
  const value = parseInt(hex.trim().slice(1), 16);
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255].map(
    (channel) => channel / 255,
  );
}

function linkProgram(gl) {
  const program = gl.createProgram();
  for (const [type, source] of [
    [gl.VERTEX_SHADER, VERTEX_SHADER],
    [gl.FRAGMENT_SHADER, FRAGMENT_SHADER],
  ]) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    gl.attachShader(program, shader);
  }
  gl.bindAttribLocation(program, 0, "a");
  gl.linkProgram(program);
  if (gl.getProgramParameter(program, gl.LINK_STATUS)) return program;
  console.warn("crescent-sky: shader failed", gl.getProgramInfoLog(program));
  return null;
}
