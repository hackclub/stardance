import { Controller } from "@hotwired/stimulus";

const PIXEL = 2;
const MAX_CLICKS = 6;
const CLICK_LIFE_S = 2.5;
const STILL_TIME_S = 12;

const VERTEX_SHADER = `
attribute vec2 a_pos;
void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }
`;

const FRAGMENT_SHADER = `
precision highp float;
uniform vec2  u_res;
uniform float u_time;
uniform vec2  u_center;
uniform float u_radius;
uniform vec3  u_border;
uniform vec4  u_guard;
uniform vec2  u_mouse;
uniform vec2  u_mvel;
uniform float u_mstr;
uniform float u_pulse;
uniform float u_clickAge[${MAX_CLICKS}];
uniform vec2  u_clickPos[${MAX_CLICKS}];

const float ZOOM = 1.45;
const float EH = 0.13;
const float CUR_K = 0.012;
const float CUR_SWIRL = 1.45;
const float CUR_CORE = 0.003;
const float CUR_SWR = 0.006;
const float CORE_R = 0.026;
const float LEVELS = 7.0;

float hash(vec2 p){ p=mod(p,512.0); p=fract(p*vec2(123.34,345.45)); p+=dot(p,p+34.345); return fract(p.x*p.y); }
float vnoise(vec2 p){
  vec2 i=floor(p), f=fract(p);
  float a=hash(i), b=hash(i+vec2(1.,0.)), c=hash(i+vec2(0.,1.)), d=hash(i+vec2(1.,1.));
  vec2 u=f*f*(3.-2.*f);
  return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
float fbm(vec2 p){
  float v=0., a=.5; mat2 m=mat2(1.6,1.2,-1.2,1.6);
  for(int i=0;i<5;i++){ v+=a*vnoise(p); p=m*p; a*=.5; }
  return v;
}

float sq(float x){ return x*x; }

float jetHalfWidth(float axl){
  float d = max(0.0, axl - 0.1625);
  return 0.013 + (0.1235 - 0.013) * exp(-d/0.416);
}

float tearDepth(vec2 frag){
  vec2 q = abs(frag - 0.5*u_res) - 0.5*u_res + u_radius;
  float inside = -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u_radius);
  float jag = fbm(frag*0.3 + vec2(u_time*0.15, -u_time*0.1));
  float chunk = hash(floor(frag/2.0) + floor(u_time*2.5)*7.3);
  return inside - 3.0*jag - 1.2*chunk;
}

float ign(vec2 p){ return fract(52.9829189*fract(dot(p, vec2(0.06711056, 0.00583715)))); }

vec2 curWarp(vec2 frag, float R, out float mr){
  vec2 d = (frag - u_mouse) / R;
  mr = length(d);
  if (u_mstr < 0.001) return frag;
  vec2 dir = d / (mr + 1e-4);
  float pull = CUR_K * mr / (mr*mr + CUR_CORE) * u_mstr;
  float sw = CUR_SWIRL * CUR_SWR / (mr*mr + CUR_SWR) * u_mstr;
  vec2 wake = u_mvel * exp(-mr*mr/0.04) * 0.06 * u_mstr;
  vec2 p = d - dir * pull - wake;
  float c = cos(sw), s = sin(sw);
  p = mat2(c, -s, s, c) * p;
  if (u_pulse >= 0.0) {
    float band = exp(-sq((mr - u_pulse*0.6)/0.03));
    p += dir * band * 0.05 * exp(-u_pulse * 1.5);
  }
  return u_mouse + p * R;
}

float scene(vec2 fragIn, out float cover, out float rim){
  float R = u_res.y;
  float mr;
  vec2 frag = curWarp(fragIn, R, mr);

  vec2 uv = (frag - u_center) / (R*ZOOM);
  float r0 = length(uv);
  uv.x /= 1.0 + 0.30*exp(-r0*r0/0.3025);
  float r = length(uv);
  vec2 cdir = uv/(r + 1e-4);

  float L = 0.0;
  float churn = fbm(cdir*2.6 + vec2(sin(u_time*0.23)*1.6, u_time*0.42)) - 0.5;
  float apert = smoothstep(EH*0.92, EH*1.04, r*(1.0 + 0.035*churn));
  if (apert > 0.0) {
    float churn2 = fbm(cdir*5.3 + vec2(-u_time*0.37, r*3.2 + u_time*0.24)) - 0.5;
    float churn3 = fbm(cdir*9.1 + vec2(u_time*0.6, r*6.0 - u_time*0.45)) - 0.5;
    float rw = r * (1.0 + 0.34*churn + 0.17*churn2);

    vec2 luv = uv - cdir * 0.024/(r*r + 0.006);
    luv.x /= 1.0 + 0.35*exp(-dot(luv,luv)/0.2116);
    float lr = length(luv);
    vec2 ldir = luv/(lr + 1e-4);
    lr *= 1.0 + 0.30*churn + 0.17*churn2 + 0.09*churn3;

    float rot = u_time*0.25/(lr + 0.12);
    vec2 rdir = mat2(cos(rot), -sin(rot), sin(rot), cos(rot)) * ldir;
    vec2 q = rdir*1.8 + vec2(lr*3.5 - u_time*0.05, 0.0);
    float turb = fbm(q*2.0 + fbm(q + vec2(0.0, u_time*0.1))*1.5);

    float stir = exp(-mr*mr/0.03) * u_mstr;
    float gust = fbm(cdir*1.7 + vec2(u_time*0.19, lr*2.2 - u_time*0.55));
    float bdith = step(0.58, hash(floor(luv*R/4.5) + floor(u_time*0.32)*3.1));
    float g = (0.013 + 0.017*bdith)
            + (0.070*turb*smoothstep(1.4, 0.2, lr) + 0.032*gust*smoothstep(1.25, 0.15, lr)) * (0.5 + 0.8*bdith);
    g += (0.022 + 0.15*turb) * stir;

    float axial = abs(luv.x);
    float writhe = (fbm(vec2(luv.x*2.9 + u_time*1.1, u_time*0.55)) - 0.5) * 0.11 * smoothstep(0.10, 0.85, axial);
    float yy = luv.y - writhe;
    float thickness = jetHalfWidth(axial);
    float band = exp(-(yy*yy)/(thickness*thickness));
    float radial = smoothstep(EH*1.05, EH*1.5, lr) * (1.0 - smoothstep(0.5, 1.25, lr));
    float kn = fbm(ldir*1.4 + vec2(lr*11.0 - u_time*1.5, u_time*0.3));
    float shock = 0.10 + 2.6*kn*kn*kn;
    float flick = 0.84 + 0.30*fbm(vec2(lr*4.2 - u_time*0.9, u_time*0.4));
    float tear = smoothstep(0.20, 0.62, fbm(ldir*2.8 + vec2(lr*6.6 - u_time*2.6, 0.0)));
    float disk = band*radial*(0.22 + 1.15*turb)*shock*flick*(0.10 + 1.05*tear);
    disk *= 1.0 + 2.0*exp(-sq((lr - EH*1.35)/0.06));
    disk *= 0.3 + 1.15*smoothstep(-1.0, 1.0, -uv.x/(r + 1e-4));

    vec2 ruv = vec2(uv.x/1.22, uv.y);
    float rq = length(ruv) * (1.0 + 0.09*churn + 0.05*churn2);
    float axialness = abs(uv.x)/(r + 1e-4);
    float rthick = 0.009 * (1.0 + 0.9*axialness);
    float rturb = fbm(cdir*4.4 + vec2(u_time*0.85, r*9.0 - u_time*0.6));
    float ring = exp(-sq((rq - EH*1.13)/rthick)) * (0.45 + 0.60*rturb) * (0.55 + 0.50*axialness);
    ring += exp(-sq(uv.y/(0.55*jetHalfWidth(abs(uv.x)))))
          * smoothstep(EH*1.1, EH*1.7, rq) * (1.0 - smoothstep(0.22, 0.55, rq))
          * axialness * axialness * (0.2 + 0.7*rturb) * 0.22;
    ring *= 1.0 + 0.25*(0.5 + 0.5*sin(u_time*2.2));
    float halo = exp(-sq((rw - EH*1.5)/0.14)) * smoothstep(0.0, 0.5, abs(uv.y)/(r + 1e-4)) * (0.3 + 0.9*turb) * 0.5;

    L = g + disk*0.8 + ring*1.15 + halo;
    float grain = fbm(rdir*8.5 + vec2(lr*19.0 - u_time*1.4, u_time*0.6)) - 0.5;
    L += grain * 0.135 * smoothstep(1.7, 0.10, lr);
  }
  L *= apert;

  vec2 gq = fragIn - u_guard.xy;
  float edge = min(min(gq.x, u_guard.z - gq.x), min(gq.y, u_guard.w - gq.y));
  L *= 1.0 - 0.6*smoothstep(-8.0, 8.0, edge);

  if (u_mstr > 0.0) {
    L *= 1.0 + 0.16 * CUR_CORE/(mr*mr + CUR_CORE) * u_mstr;
    L += exp(-sq((mr - CORE_R*1.22)/0.007)) * 0.95 * u_mstr;
    if (u_pulse >= 0.0) {
      L += exp(-sq((mr - u_pulse*0.6)/0.03)) * 0.30 * exp(-u_pulse*1.5) * u_mstr;
    }
  }

  float bs = 5.0;
  vec2 cell = floor(fragIn/bs);
  vec2 ctr = (cell + 0.5)*bs;
  float jit = (hash(cell) - 0.5)*2.8;
  float ck = 0.0;
  for (int i = 0; i < ${MAX_CLICKS}; i++) {
    if (u_clickAge[i] < 0.0) continue;
    float delta = u_clickAge[i]*16.0 - (floor(length(ctr - u_clickPos[i])/bs) + jit);
    ck += step(0.0, delta) * (1.0 - step(3.0, delta)) * (1.0 - delta/3.0);
  }
  L = (L + ck*0.06) * (1.0 + ck*0.45);

  float depth = tearDepth(fragIn);
  L *= 0.45 + 0.55*smoothstep(1.0, 18.0, depth);
  cover = step(ign(floor(fragIn) + 17.0), smoothstep(-0.5, 1.0, depth));
  rim = 1.0 - step(1.5, depth);

  L = L < 0.72 ? L : 0.72 + (L - 0.72)/(1.0 + (L - 0.72)*2.4);
  L *= mix(1.0, smoothstep(CORE_R*0.88, CORE_R*1.03, mr), u_mstr);
  return clamp(L, 0.0, 1.0);
}

vec3 ramp(float q){
  vec3 shadow = vec3(0.020, 0.020, 0.028);
  vec3 mid = vec3(0.34, 0.32, 0.33);
  vec3 light = vec3(0.94, 0.92, 0.89);
  return q < 0.5 ? mix(shadow, mid, q*2.0) : mix(mid, light, (q - 0.5)*2.0);
}

void main(){
  float cover, rim;
  float v = scene(gl_FragCoord.xy, cover, rim) * LEVELS;
  float q = clamp((floor(v) + step(ign(floor(gl_FragCoord.xy)), fract(v)))/LEVELS, 0.0, 1.0);
  vec3 col = mix(ramp(q), u_border, rim);
  gl_FragColor = vec4(col * cover, cover);
}
`;

export default class extends Controller {
  static targets = ["canvas", "horizon", "copy"];
  static classes = ["torn"];

  connect() {
    this.reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.visible = false;
    this.time = this.reduceMotion ? STILL_TIME_S : 0;
    this.mouse = { x: 0, y: 0 };
    this.mouseVel = { x: 0, y: 0 };
    this.mouseStrength = 0;
    this.hovering = false;
    this.clicks = [];
    this.onVisibility = () => this.syncLoop();
    document.addEventListener("visibilitychange", this.onVisibility);

    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting;
        if (this.visible && !this.gl) this.boot();
        this.syncLoop();
      },
      { rootMargin: "120px" },
    );
    this.observer.observe(this.element);
  }

  disconnect() {
    this.observer?.disconnect();
    document.removeEventListener("visibilitychange", this.onVisibility);
    cancelAnimationFrame(this.frame);
    this.running = false;
    this.gl?.getExtension("WEBGL_lose_context")?.loseContext();
    this.gl = null;
  }

  boot() {
    const gl = this.canvasTarget.getContext("webgl", { antialias: false });
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
    const pos = gl.getAttribLocation(program, "a_pos");
    gl.enableVertexAttribArray(pos);
    gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);

    this.gl = gl;
    this.uniforms = Object.fromEntries(
      [
        "u_res",
        "u_time",
        "u_center",
        "u_radius",
        "u_border",
        "u_guard",
        "u_mouse",
        "u_mvel",
        "u_mstr",
        "u_pulse",
        "u_clickAge",
        "u_clickPos",
      ].map((name) => [name, gl.getUniformLocation(program, name)]),
    );

    this.border = getComputedStyle(this.element)
      .borderTopColor.match(/[\d.]+/g)
      .slice(0, 3)
      .map((channel) => channel / 255);
    this.element.classList.add(...this.tornClasses);
    this.draw();
  }

  enter(e) {
    this.lastMove = null;
    this.track(e);
    this.hovering = true;
  }

  leave() {
    this.hovering = false;
  }

  press(e) {
    if (!this.interactive) return;
    this.track(e);
    this.clicks.push({ ...this.mouse, age: 0 });
    if (this.clicks.length > MAX_CLICKS) this.clicks.shift();
  }

  track(e) {
    if (!this.interactive) return;
    const { x, y } = this.toBuffer(e.clientX, e.clientY);
    if (this.lastMove) {
      const dt = Math.max(0.001, (e.timeStamp - this.lastMove.at) / 1000);
      const height = Math.max(1, this.canvasTarget.height);
      this.mouseVel.x = (x - this.lastMove.x) / height / dt;
      this.mouseVel.y = (y - this.lastMove.y) / height / dt;
    }
    this.lastMove = { x, y, at: e.timeStamp };
    this.mouse = { x, y };
  }

  get interactive() {
    return this.gl && !this.reduceMotion;
  }

  syncLoop() {
    const shouldRun = this.interactive && this.visible && !document.hidden;
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
    if (!this.running || !this.gl) return;
    const dt = this.lastTick ? Math.min(0.1, (now - this.lastTick) / 1000) : 0;
    this.lastTick = now;
    this.time += dt;

    const ease = 1 - Math.exp(-dt * 6);
    this.mouseStrength += ((this.hovering ? 1 : 0) - this.mouseStrength) * ease;
    this.mouseVel.x *= 1 - ease;
    this.mouseVel.y *= 1 - ease;
    this.clicks.forEach((click) => (click.age += dt));
    this.clicks = this.clicks.filter((click) => click.age < CLICK_LIFE_S);

    this.draw();
    this.frame = requestAnimationFrame((t) => this.tick(t));
  }

  draw() {
    const { gl, uniforms: u } = this;
    this.resize();

    const ages = new Float32Array(MAX_CLICKS).fill(-1);
    const positions = new Float32Array(MAX_CLICKS * 2);
    this.clicks.forEach((click, i) => {
      ages[i] = click.age;
      positions.set([click.x, click.y], i * 2);
    });
    const latest = this.clicks[this.clicks.length - 1];

    gl.uniform2f(u.u_res, gl.drawingBufferWidth, gl.drawingBufferHeight);
    gl.uniform1f(u.u_time, this.time);
    const horizon = this.horizonTarget.getBoundingClientRect();
    const center = this.toBuffer(
      horizon.left + horizon.width / 2,
      horizon.top + horizon.height / 2,
    );
    gl.uniform2f(u.u_center, center.x, center.y);
    gl.uniform1f(u.u_radius, this.radius);
    gl.uniform3fv(u.u_border, this.border);
    const copy = this.copyTarget.getBoundingClientRect();
    const corner = this.toBuffer(copy.left, copy.bottom);
    gl.uniform4f(
      u.u_guard,
      corner.x,
      corner.y,
      copy.width / PIXEL,
      copy.height / PIXEL,
    );
    gl.uniform2f(u.u_mouse, this.mouse.x, this.mouse.y);
    gl.uniform2f(u.u_mvel, this.mouseVel.x, this.mouseVel.y);
    gl.uniform1f(u.u_mstr, this.mouseStrength);
    gl.uniform1f(u.u_pulse, latest ? latest.age : -1);
    gl.uniform1fv(u.u_clickAge, ages);
    gl.uniform2fv(u.u_clickPos, positions);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  toBuffer(clientX, clientY) {
    const rect = this.canvasTarget.getBoundingClientRect();
    return {
      x: (clientX - rect.left) / PIXEL,
      y: (rect.bottom - clientY) / PIXEL,
    };
  }

  resize() {
    const canvas = this.canvasTarget;
    const width = Math.max(1, Math.round(canvas.clientWidth / PIXEL));
    const height = Math.max(1, Math.round(canvas.clientHeight / PIXEL));
    if (canvas.width === width && canvas.height === height) return;
    canvas.width = width;
    canvas.height = height;
    this.radius =
      parseFloat(getComputedStyle(this.element).borderTopLeftRadius) / PIXEL;
    this.gl.viewport(0, 0, width, height);
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
  console.warn("black-hole: shader failed", gl.getProgramInfoLog(program));
  return null;
}
