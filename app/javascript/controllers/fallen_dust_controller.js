import { Controller } from "@hotwired/stimulus";

// Fallen's landing dust (fallen platform, components/shaders/particles.ts),
// cut down to the card: small faint polygons drifting along a soft diagonal
// band, lit from the top right and each shimmering now and then. Ambient only:
// the cursor glow, the tilt, the shards and the camera parallax stay behind.

const AXIS = 60; // the field starts as an AXIS x AXIS grid, scattered
const MAX_DPR = 2;
const FRAME_MS = 1000 / 30; // the dust drifts slowly, so 30fps looks the same as 60
// Long past every particle's fade in: the field as it settles.
const STILL_TIME_S = 20;

const VERTEX_SHADER = `#version 300 es
// The camera sits still at z = 5 looking at the flat field, with a 75 degree
// vertical field of view, so projecting is just a constant scale.
const float CAMERA_Z = 5.0;
const float FOCAL = 1.3032254; // 1 / tan(75 degrees / 2)

in vec2 position;
in float sizes;
in float shapes;
in float rotations;
in float spins;
in float fadeIns; // seconds this particle takes to fade in

uniform float uTime;
uniform float uAspect;

out float vSeed;
out float vAngle;
out float vTumble;
out float vDiffuse;
out float vFadeIn;
out float vBand;
out float vShimmer;

void main() {
  vec2 p = position;

  vSeed = shapes;
  vFadeIn = smoothstep(0.0, fadeIns, uTime);

  vAngle = rotations + uTime * spins;
  // each shape flips around its own in-plane axis while it spins
  float flip = uTime * spins * 0.8 + rotations;
  vTumble = 0.35 + 0.65 * abs(cos(flip));

  // the shape's surface normal in 3D, from its spin and flip
  vec2 flipAxis = vec2(cos(vAngle), sin(vAngle));
  vec3 normal = vec3(flipAxis * sin(flip), cos(flip));

  // light from the top right; flat shapes reflect off both faces
  vec3 lightDir = normalize(vec3(0.5, 0.6, 0.7));
  vDiffuse = abs(dot(normal, lightDir));

  float speed = 0.04 + shapes * 0.05;

  p.x += mod(position.x + 6.0 - uTime * speed + 12.0, 12.0) - 6.0;
  p.y += mod(position.y + 4.0 - uTime * speed * 0.7 + 8.0, 8.0) - 4.0;

  gl_Position = vec4(p.x * FOCAL / uAspect, p.y * FOCAL, 0.0, CAMERA_Z);
  gl_PointSize = sizes * 300.0 / CAMERA_Z;

  // only show inside a gently wavy band running bottom left to top right
  vec2 onScreen = p * FOCAL / CAMERA_Z;
  float fromBand = dot(onScreen, normalize(vec2(-0.7, 1.0)));
  fromBand += 0.08 * sin(onScreen.x * 5.0);
  vBand = 1.0 - smoothstep(0.12, 0.4, abs(fromBand));

  // outside the band or not faded in yet: move it off screen so the GPU skips
  // its pixels entirely instead of drawing them see-through
  if (vBand * vFadeIn <= 0.0) gl_Position = vec4(2.0, 2.0, 2.0, 1.0);

  // mostly steady, with a short bright flash every few seconds
  float wave = 0.5 + 0.5 * sin(uTime * (0.6 + fadeIns) + rotations * 7.0);
  vShimmer = 0.7 + 1.8 * pow(wave, 12.0);
}`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;

in float vSeed;
in float vAngle;
in float vTumble;
in float vDiffuse;
in float vFadeIn;
in float vBand;
in float vShimmer;

out vec4 fragColor;

float hash(float n) {
  return fract(sin(n) * 43758.5453);
}

// max() that blends the two shapes over a width of k instead of meeting at a sharp corner
float smax(float a, float b, float k) {
  if (k <= 0.0) return max(a, b);
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(a, b, h) + k * h * (1.0 - h);
}

void main() {
  vec2 uv = gl_PointCoord - vec2(0.5);

  float c = cos(vAngle);
  float s = sin(vAngle);
  uv = mat2(c, -s, s, c) * uv;
  uv.x /= vTumble;

  float h1 = hash(vSeed * 91.7);
  float h3 = hash(vSeed * 13.1 + 2.0);

  // irregular convex polygon: 4-6 edges at jittered angles and distances.
  // some edges bulge into curves and some corners melt smoothly into the next edge
  float sides = 4.0 + floor(h1 * 3.0);
  float rounding = mix(0.01, 0.03, h3);
  float d = -1.0;
  for (int i = 0; i < 6; i++) {
    if (float(i) >= sides) break;
    float fi = float(i);
    float a = (fi + (hash(vSeed * 17.0 + fi) - 0.5) * 0.3) * 6.2831853 / sides;
    float h = mix(0.13, 0.22, hash(vSeed * 29.0 + fi * 3.7)) - rounding;
    vec2 n = vec2(cos(a), sin(a));

    float edge = dot(uv, n) - h;
    if (hash(vSeed * 53.0 + fi * 5.1) > 0.5) {
      // curved edge: a circle tangent to where the straight edge would be
      float r = mix(0.25, 0.6, hash(vSeed * 61.0 + fi * 2.3));
      edge = length(uv + n * (r - h)) - r;
    }

    float k = hash(vSeed * 71.0 + fi * 4.1) > 0.6 ? 0.12 : 0.0;
    d = smax(d, edge, k);
  }
  d -= rounding;

  float alpha = 1.0 - smoothstep(-0.006, 0.006, d);
  if (alpha < 0.01) discard;

  // light catching the edges
  float rim = smoothstep(-0.05, 0.0, d);

  vec3 colorA = vec3(1.0, 0.88, 0.82);
  vec3 colorB = vec3(0.96, 0.78, 0.84);
  vec3 colorC = vec3(0.85, 0.86, 1.0);

  vec3 color = mix(colorA, colorB, vSeed);
  color = mix(color, colorC, smoothstep(0.75, 1.0, vSeed));

  // a rare few are green (#C7E1B8)
  if (hash(vSeed * 37.3 + 5.0) > 0.93) color = vec3(0.78, 0.882, 0.722);

  // faint when facing away from the light
  float lit = 0.12 + 0.28 * vDiffuse + 0.1 * rim * vDiffuse;
  float intensity = alpha * lit * vShimmer * vFadeIn * vBand;

  // additive blending multiplies rgb by alpha, so alpha is how much light gets added
  fragColor = vec4(color, clamp(intensity, 0.0, 1.0));
}`;

export default class extends Controller {
  static targets = ["canvas"];

  connect() {
    this.still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.time = this.still ? STILL_TIME_S : 0;
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

  // The WebGL context is kept rather than lost on purpose: if this element
  // reconnects, its canvas would hand back the lost context and the dust
  // could never draw again. The browser frees it with the canvas.
  disconnect() {
    this.intersectionObserver?.disconnect();
    this.resizeObserver?.disconnect();
    document.removeEventListener("visibilitychange", this.onVisibility);
    this.running = false;
    cancelAnimationFrame(this.frame);
  }

  boot() {
    const gl = this.canvasTarget.getContext("webgl2", {
      alpha: true,
      antialias: false,
      depth: false,
      powerPreference: "low-power",
    });
    if (!gl) return; // no WebGL2: the card just goes without the dust

    const program = linkProgram(gl);
    if (!program) return;

    this.vao = gl.createVertexArray();
    gl.bindVertexArray(this.vao);
    for (const [name, data] of Object.entries(scatter())) {
      const location = gl.getAttribLocation(program, name);
      if (location < 0) continue;
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(location);
      gl.vertexAttribPointer(
        location,
        name === "position" ? 2 : 1,
        gl.FLOAT,
        false,
        0,
        0,
      );
    }
    gl.bindVertexArray(null);

    gl.useProgram(program);
    gl.enable(gl.BLEND);
    // additive, so overlapping particles add up to brighter light
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE);
    gl.clearColor(0, 0, 0, 0);

    this.uniforms = {
      uTime: gl.getUniformLocation(program, "uTime"),
      uAspect: gl.getUniformLocation(program, "uAspect"),
    };
    this.gl = gl;
    this.draw();
  }

  syncLoop() {
    const shouldRun =
      this.gl && !this.still && this.visible && !document.hidden;
    if (shouldRun && !this.running) {
      this.running = true;
      this.lastTick = null;
      this.lastDraw = -Infinity;
      this.frame = requestAnimationFrame((now) => this.tick(now));
    } else if (!shouldRun && this.running) {
      this.running = false;
      cancelAnimationFrame(this.frame);
    }
  }

  tick(now) {
    if (!this.running) return;
    this.frame = requestAnimationFrame((next) => this.tick(next));
    // capped so a stalled frame doesn't jump everything forward
    const delta =
      this.lastTick == null ? 0 : Math.min((now - this.lastTick) / 1000, 0.1);
    this.lastTick = now;
    this.time += delta;

    if (now - this.lastDraw < FRAME_MS) return;
    this.lastDraw = now;
    this.draw();
  }

  draw() {
    const { gl, uniforms: u } = this;
    if (!gl || !this.updateLayout()) return;

    gl.uniform1f(u.uTime, this.time);

    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.bindVertexArray(this.vao);
    gl.drawArrays(gl.POINTS, 0, AXIS * AXIS);
    gl.bindVertexArray(null);
  }

  // match the drawing buffer to the canvas's size on screen, in device pixels
  updateLayout() {
    if (!this.layoutDirty) return true;
    const rect = this.canvasTarget.getBoundingClientRect();
    if (!rect.width || !rect.height) return false;
    const ratio = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    const width = Math.max(1, Math.round(rect.width * ratio));
    const height = Math.max(1, Math.round(rect.height * ratio));
    const { gl, uniforms: u } = this;
    this.canvasTarget.width = width;
    this.canvasTarget.height = height;
    gl.viewport(0, 0, width, height);
    gl.uniform1f(u.uAspect, width / height);
    this.layoutDirty = false;
    return true;
  }
}

// Each particle's starting place, size, shape seed, spin and fade in time.
function scatter() {
  const count = AXIS * AXIS;
  const attributes = {
    position: new Float32Array(count * 2),
    sizes: new Float32Array(count),
    shapes: new Float32Array(count),
    rotations: new Float32Array(count),
    spins: new Float32Array(count),
    fadeIns: new Float32Array(count),
  };
  let i = 0;
  for (let x = 0; x < AXIS; x++) {
    for (let y = 0; y < AXIS; y++) {
      attributes.position[i * 2] =
        (x - AXIS / 2) * 0.08 * (Math.random() - 0.5) * 40;
      attributes.position[i * 2 + 1] =
        (y - AXIS / 2) * 0.12 * (Math.random() - 0.5) * 40;
      attributes.sizes[i] = 0.04 + Math.random() * 0.4;
      attributes.shapes[i] = Math.random();
      attributes.rotations[i] = Math.random() * Math.PI * 2;
      attributes.spins[i] = (Math.random() - 0.5) * 0.6;
      // each fades in over its own time, so they appear one by one
      attributes.fadeIns[i] = 0.6 + Math.random() * 1.4;
      i++;
    }
  }
  return attributes;
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
  gl.linkProgram(program);
  if (gl.getProgramParameter(program, gl.LINK_STATUS)) return program;
  console.warn("fallen-dust: shader failed", gl.getProgramInfoLog(program));
  return null;
}
