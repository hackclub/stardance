// The wall of fire that climbs the screen when the Forge card is clicked, drawn
// per pixel in WebGL so its flames keep crisp edges at any size. Tall noise
// scrolls upward through the wavefront and is cut into hard bands of colour,
// and everything below it keeps burning until the whole screen is ablaze. Then
// the flames die down to charred black ground, cracked with embers that cool.
// Lengths in the shader are in CSS pixels.
const VERTEX_SHADER = `
attribute vec2 a_pos;
void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }
`;

const FRAGMENT_SHADER = `
precision highp float;
uniform vec2 u_size;
uniform float u_scale, u_time, u_front, u_fade, u_reach;
uniform vec3 u_core, u_flame, u_ember, u_soot;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float noise(vec2 x) {
  vec2 i = floor(x), f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
  return v;
}
// A hard edge, softened by about a pixel so it doesn't alias.
float band(float edge, float h) { return smoothstep(edge, edge + 0.015, h); }

void main() {
  vec2 p = vec2(gl_FragCoord.x, u_size.y - gl_FragCoord.y) / u_scale;
  float t = u_time;
  // A ragged front that surges unevenly across the screen.
  float front = u_front + (fbm(vec2(p.x * 0.004, t * 0.8)) - 0.5) * u_reach * 0.35
              + sin(p.x * 0.011 + t * 6.0) * 22.0 + sin(p.x * 0.027 - t * 11.0) * 10.0;
  // Positive below the front, where the fire has already passed.
  float d = p.y - front;

  // Noise stretched tall and scrolled upward, warped by itself so the tongues lick and curl.
  vec2 q = vec2(p.x * 0.014, p.y * 0.0028 + t * 3.6);
  float n = fbm(q + (fbm(q * 1.8 - t * 0.6) - 0.5) * 0.9);
  // Finer, faster licks break up the tips.
  n = n * 0.8 + fbm(vec2(p.x * 0.05, p.y * 0.012 + t * 6.0)) * 0.2;

  // The wall's flames tower u_reach above its front, and everything it has passed stays alight.
  // Big, slow pockets of cooler fire roll up through the blaze so it never burns one flat yellow.
  float heat = smoothstep(-u_reach, 0.0, d)
             * (0.62 + 0.55 * fbm(vec2(p.x * 0.004, p.y * 0.003 + t * 1.5) + 11.0));
  // Dying down shrinks the flames into themselves rather than ghosting them out.
  float h = heat * 1.4 - n * 1.1 - u_fade * 1.5;
  float fire = band(0.2, h);
  vec3 col = mix(u_ember, u_soot, 0.35);
  col = mix(col, u_ember, band(0.32, h));
  col = mix(col, u_flame, band(0.48, h));
  col = mix(col, u_core, band(0.74, h));
  col = mix(col, vec3(1.0), band(0.98, h) * 0.5);

  // Charred ground behind the front, with glowing cracks that cool the further back they lie.
  float charred = max(u_fade, smoothstep(-10.0, 90.0, d + (n - 0.5) * 120.0));
  // Only some stretches of each crack are still lit, so they read as embers rather than contour lines.
  float crack = (1.0 - smoothstep(0.0, 0.012, abs(fbm(p * 0.018 + 7.0) - 0.52)))
              * smoothstep(0.45, 0.6, noise(p * 0.012 + 3.0));
  float cooling = (1.0 - smoothstep(80.0, 700.0, d)) * (1.0 - u_fade);
  vec3 ground = u_soot + mix(u_ember, u_flame, cooling) * crack * cooling * 0.9;

  // A heat glow washes over the page just ahead of the flames.
  float glow = smoothstep(-1.6 * u_reach, 0.0, d) * (1.0 - charred) * (1.0 - u_fade) * 0.5;

  vec3 rgb = ground * charred;
  float alpha = charred;
  rgb += u_ember * glow * (1.0 - alpha);
  alpha += glow * (1.0 - alpha);
  rgb = rgb * (1.0 - fire) + col * fire;
  alpha = alpha * (1.0 - fire) + fire;
  gl_FragColor = vec4(rgb, alpha);
}
`;

const UNIFORMS = [
  "u_size",
  "u_scale",
  "u_time",
  "u_front",
  "u_fade",
  "u_reach",
  "u_core",
  "u_flame",
  "u_ember",
  "u_soot",
];
const COLORS = ["core", "flame", "ember", "soot"];

export default class FireWave {
  static create(canvas, colors) {
    const shader = createShader(canvas, FRAGMENT_SHADER, UNIFORMS);
    return shader && new FireWave(shader, colors);
  }

  constructor({ gl, uniforms }, colors) {
    this.gl = gl;
    this.uniforms = uniforms;
    for (const name of COLORS)
      gl.uniform3fv(uniforms[`u_${name}`], toRgb(colors[name]));
  }

  // `scale` is canvas pixels per CSS pixel.
  resize(width, height, scale) {
    const { gl, uniforms: u } = this;
    gl.canvas.width = width;
    gl.canvas.height = height;
    gl.viewport(0, 0, width, height);
    gl.uniform2f(u.u_size, width, height);
    gl.uniform1f(u.u_scale, scale);
  }

  // `front` is how far down the screen the fire's edge is and `reach` how high its flames tower
  // above it, in CSS pixels; `fade` runs from 0 to 1 as it dies down.
  draw({ time, front, reach, fade }) {
    const { gl, uniforms: u } = this;
    gl.uniform1f(u.u_time, time);
    gl.uniform1f(u.u_front, front);
    gl.uniform1f(u.u_fade, fade);
    gl.uniform1f(u.u_reach, reach);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  destroy() {
    this.gl.getExtension("WEBGL_lose_context")?.loseContext();
  }
}

// Returns the context and the named uniforms, or null when WebGL or the shader is unavailable.
function createShader(canvas, fragmentShader, uniformNames) {
  const gl = canvas.getContext("webgl", { antialias: false });
  if (!gl) return null;
  const program = linkProgram(gl, fragmentShader);
  if (!program) return null;
  gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
    gl.STATIC_DRAW,
  );
  const pos = gl.getAttribLocation(program, "a_pos");
  gl.enableVertexAttribArray(pos);
  gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);
  const uniforms = Object.fromEntries(
    uniformNames.map((name) => [name, gl.getUniformLocation(program, name)]),
  );
  return { gl, uniforms };
}

function linkProgram(gl, fragmentShader) {
  const program = gl.createProgram();
  [
    [gl.VERTEX_SHADER, VERTEX_SHADER],
    [gl.FRAGMENT_SHADER, fragmentShader],
  ].forEach(([type, source]) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    gl.attachShader(program, shader);
  });
  gl.linkProgram(program);
  if (gl.getProgramParameter(program, gl.LINK_STATUS)) return program;
  console.warn("forge-promo: shader failed", gl.getProgramInfoLog(program));
  return null;
}

let colorProbe;
function toRgb(color) {
  colorProbe ??= document
    .createElement("canvas")
    .getContext("2d", { willReadFrequently: true });
  colorProbe.clearRect(0, 0, 1, 1);
  colorProbe.fillStyle = color;
  colorProbe.fillRect(0, 0, 1, 1);
  const [r, g, b] = colorProbe.getImageData(0, 0, 1, 1).data;
  return [r / 255, g / 255, b / 255];
}
