const VERTEX_SHADER = `
attribute vec2 a_pos;
varying vec2 v_uv;
void main() { v_uv = a_pos * 0.5 + 0.5; gl_Position = vec4(a_pos, 0.0, 1.0); }
`;

const FRAGMENT_SHADER = `
precision highp float;
varying vec2 v_uv;
uniform float u_time, u_surge, u_lens, u_hole;
uniform sampler2D u_tex;
uniform vec3 u_deep, u_mid, u_hi, u_glint;
const float TAU = 6.2831853;

float hash31(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float noise(vec3 x) {
  vec3 i = floor(x), f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.02 + vec3(3.1, 1.7, 5.3); a *= 0.5; }
  return v;
}
float glint(vec2 d, float s) {
  float core = exp(-length(d) / (0.012 * s));
  float rays = exp(-abs(d.x) / (0.004 * s)) * exp(-abs(d.y) / (0.09 * s)) + exp(-abs(d.y) / (0.004 * s)) * exp(-abs(d.x) / (0.09 * s));
  vec2 e = vec2(d.x + d.y, d.x - d.y) * 0.7071;
  float diag = exp(-abs(e.x) / (0.003 * s)) * exp(-abs(e.y) / (0.04 * s)) + exp(-abs(e.y) / (0.003 * s)) * exp(-abs(e.x) / (0.04 * s));
  return core * 1.4 + rays * 0.8 + diag * 0.35;
}

void main() {
  vec2 p = v_uv * 2.0 - 1.0;
  float r = length(p);
  float a = atan(p.y, p.x);
  float t = u_time;

  vec2 cs1 = vec2(cos(a - t * 0.45), sin(a - t * 0.45));
  vec2 cs2 = vec2(cos(a - t * 0.7), sin(a - t * 0.7));
  vec2 drift = vec2(sin(t * 0.31), cos(t * 0.23)) * 0.5;
  float warp = fbm(vec3(cs1 * 1.3 + drift, r * 2.0 + t * 0.35));
  float warp2 = fbm(vec3(cs1 * 2.2 - drift, r * 3.0 - t * 0.42) + warp * 1.6);
  float rr = r + (warp - 0.5) * 0.26 + (warp2 - 0.5) * 0.12;
  float smoke = fbm(vec3(cs1 * 1.8 + (warp2 - 0.5) * 1.4, rr * 6.0 - t * 0.3 + warp * 2.0));
  float streak = fbm(vec3(cs2 * 1.0 + 4.0 + warp2 * 0.8, rr * 18.0 + t * 0.25));

  float ringR = 0.6 + 0.035 * sin(a * 2.0 + t * 0.7) + 0.025 * sin(a * 3.0 - t * 1.1 + warp * 3.0);
  float ringW = 0.12 + 0.035 * sin(a * 3.0 + t * 0.9 + warp2 * 4.0);
  float band = exp(-pow((rr - ringR) / ringW, 2.0));
  float outer = exp(-pow((rr - ringR - 0.18) / 0.16, 2.0)) * 0.55;
  float dens = band * smoothstep(0.3, 0.75, smoke) * (0.6 + 0.8 * streak)
             + outer * pow(smoothstep(0.35, 0.85, smoke), 2.0);
  dens *= (1.0 + u_surge * 0.8) * smoothstep(1.0, 0.85, r);

  vec3 col = mix(u_deep, u_mid, smoothstep(0.1, 0.7, dens));
  col = mix(col, u_hi, smoothstep(0.6, 1.2, dens));
  col += u_glint * smoothstep(1.0, 1.6, dens) * 0.6;
  float alpha = clamp(dens * 1.6, 0.0, 1.0);

  float sectors = 16.0;
  float id0 = floor((a - t * 0.4) / TAU * sectors);
  float sparkle = 0.0;
  for (int k = -1; k <= 1; k++) {
    float id = id0 + float(k);
    float idm = mod(id, sectors);
    float h = hash11(idm + 1.0);
    if (h < 0.3) continue;
    float h2 = hash11(idm + 7.3), h3 = hash11(idm + 19.1);
    float ca = (id + 0.5 + (h2 - 0.5) * 0.7) / sectors * TAU + t * 0.4;
    vec2 c = (0.6 + (h3 - 0.5) * 0.32) * vec2(cos(ca), sin(ca));
    float twinkle = 0.3 + 0.7 * pow(0.5 + 0.5 * sin(t * (1.2 + h * 2.5) + h * 40.0), 3.0);
    sparkle += glint(p - c, 0.8 + h * 0.7) * twinkle;
  }
  col += u_glint * sparkle;
  alpha = max(alpha, clamp(sparkle, 0.0, 1.0));

  // u_lens relaxes to 0 before the zoom so the hole matches the flat image underneath, then u_hole hands over to it.
  float hole = (1.0 - smoothstep(ringR - 0.18, ringR, rr)) * u_hole;
  float sa = a + 1.2 * pow(clamp(r / 0.6, 0.0, 1.0), 3.0) * (1.0 + u_surge * 2.0) * u_lens;
  vec2 q = vec2(cos(sa), sin(sa)) * r * (1.0 - 0.18 * pow(r / 0.6, 2.0) * u_lens);
  vec3 img = texture2D(u_tex, q / 1.2 + 0.5).rgb;
  img = mix(img, u_deep * 0.4, smoothstep(0.3, 0.6, r) * 0.5 * u_lens);

  gl_FragColor = vec4(img * hole * (1.0 - alpha) + col * alpha, hole + alpha * (1.0 - hole));
}
`;

const UNIFORMS = [
  "u_time",
  "u_surge",
  "u_lens",
  "u_hole",
  "u_deep",
  "u_mid",
  "u_hi",
  "u_glint",
];

export default class ShaderRing {
  static create(canvas) {
    const gl = canvas.getContext("webgl", { antialias: false });
    if (!gl) return null;
    const program = linkProgram(gl);
    return program ? new ShaderRing(gl, program) : null;
  }

  constructor(gl, program) {
    this.gl = gl;
    this.lens = 1;
    this.hole = 1;
    this.holeOpen = false;

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

    gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    this.uniforms = Object.fromEntries(
      UNIFORMS.map((name) => [name, gl.getUniformLocation(program, name)]),
    );
  }

  resize(size) {
    const { canvas } = this.gl;
    canvas.width = canvas.height = size;
    this.gl.viewport(0, 0, size, size);
  }

  setColors(colors) {
    for (const [name, rgb] of Object.entries(colors))
      this.gl.uniform3fv(this.uniforms[`u_${name}`], rgb);
  }

  setDestination(image) {
    const { gl } = this;
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, image);
  }

  openHole() {
    this.holeOpen = true;
  }

  closeHole() {
    this.holeOpen = false;
  }

  // Straighten the lensing first, then fade the hole; reverse order when closing.
  easeHole(dt) {
    const ease = 1 - Math.exp(-dt * 8);
    if (this.holeOpen) {
      this.lens -= this.lens * ease;
      if (this.lens < 0.02) this.hole -= this.hole * ease;
    } else {
      this.hole += (1 - this.hole) * ease;
      if (this.hole > 0.98) this.lens += (1 - this.lens) * ease;
    }
  }

  draw({ time, dt, surge }) {
    const { gl, uniforms: u } = this;
    this.easeHole(dt);
    gl.uniform1f(u.u_time, time);
    gl.uniform1f(u.u_surge, surge);
    gl.uniform1f(u.u_lens, this.lens);
    gl.uniform1f(u.u_hole, this.hole);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  destroy() {
    this.gl.getExtension("WEBGL_lose_context")?.loseContext();
  }
}

function linkProgram(gl) {
  const program = gl.createProgram();
  [
    [gl.VERTEX_SHADER, VERTEX_SHADER],
    [gl.FRAGMENT_SHADER, FRAGMENT_SHADER],
  ].forEach(([type, source]) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    gl.attachShader(program, shader);
  });
  gl.linkProgram(program);
  if (gl.getProgramParameter(program, gl.LINK_STATUS)) return program;
  console.warn("terra-portal: shader failed", gl.getProgramInfoLog(program));
  return null;
}
