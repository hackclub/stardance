// Thermal-printer noise, synthesised so there's no audio file to ship. Ported
// from receipt.hackclub.com: the feed motor hum, the stepper ratchet that gives
// it the grainy "zzzt", paper hiss, and a little cut-bar clack at the end.

let ctx = null;
let noiseBuffer = null;

function audioContext() {
  if (ctx) return ctx;
  const Ctor = window.AudioContext || window.webkitAudioContext;
  if (!Ctor) return null;
  ctx = new Ctor();
  return ctx;
}

// One second of white noise, reused by every layer at different filters.
function noise(context) {
  if (noiseBuffer) return noiseBuffer;
  noiseBuffer = context.createBuffer(1, context.sampleRate, context.sampleRate);
  const data = noiseBuffer.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  return noiseBuffer;
}

// Browsers keep the context suspended until a user gesture, so call this from
// the click handler before playing.
export async function primeAudio() {
  const context = audioContext();
  if (context?.state === "suspended") await context.resume().catch(() => {});
  return context?.state === "running";
}

export function playPrinterSound({
  delay = 0,
  duration = 1.5,
  volume = 0.4,
} = {}) {
  const context = audioContext();
  if (!context || context.state !== "running") return;

  const start = context.currentTime + delay;
  const end = start + duration;

  const out = context.createGain();
  out.gain.setValueAtTime(0, start);
  out.gain.linearRampToValueAtTime(volume, start + 0.05);
  out.gain.setValueAtTime(volume, end - 0.09);
  out.gain.linearRampToValueAtTime(0, end);
  out.connect(context.destination);

  // Motor hum: a dull saw that spins up and settles.
  const motor = context.createOscillator();
  motor.type = "sawtooth";
  motor.frequency.setValueAtTime(52, start);
  motor.frequency.linearRampToValueAtTime(74, start + 0.18);
  motor.frequency.linearRampToValueAtTime(69, end);
  const motorTone = context.createBiquadFilter();
  motorTone.type = "lowpass";
  motorTone.frequency.value = 620;
  const motorGain = context.createGain();
  motorGain.gain.value = 0.16;
  motor.connect(motorTone).connect(motorGain).connect(out);

  // Stepper ratchet: bandpassed noise chopped by a fast square LFO.
  const stepper = context.createBufferSource();
  stepper.buffer = noise(context);
  stepper.loop = true;
  const stepperTone = context.createBiquadFilter();
  stepperTone.type = "bandpass";
  stepperTone.frequency.value = 1750;
  stepperTone.Q.value = 1.4;
  const chop = context.createGain();
  chop.gain.value = 0.35;
  const lfo = context.createOscillator();
  lfo.type = "square";
  lfo.frequency.setValueAtTime(44, start);
  lfo.frequency.linearRampToValueAtTime(58, end);
  const lfoDepth = context.createGain();
  lfoDepth.gain.value = 0.3;
  lfo.connect(lfoDepth).connect(chop.gain);
  stepper.connect(stepperTone).connect(chop).connect(out);

  // Paper hiss riding over the top.
  const hiss = context.createBufferSource();
  hiss.buffer = noise(context);
  hiss.loop = true;
  const hissTone = context.createBiquadFilter();
  hissTone.type = "highpass";
  hissTone.frequency.value = 3200;
  const hissGain = context.createGain();
  hissGain.gain.value = 0.1;
  hiss.connect(hissTone).connect(hissGain).connect(out);

  // Cut bar: one short clack as the paper finishes.
  const clack = context.createBufferSource();
  clack.buffer = noise(context);
  const clackTone = context.createBiquadFilter();
  clackTone.type = "bandpass";
  clackTone.frequency.value = 2600;
  clackTone.Q.value = 0.9;
  const clackGain = context.createGain();
  clackGain.gain.setValueAtTime(volume * 0.5, end);
  clackGain.gain.exponentialRampToValueAtTime(0.0001, end + 0.07);
  clack.connect(clackTone).connect(clackGain).connect(context.destination);

  for (const node of [motor, stepper, lfo, hiss]) {
    node.start(start);
    node.stop(end + 0.02);
  }
  clack.start(end);
  clack.stop(end + 0.09);
}
