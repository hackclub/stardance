// The Forge card's burnt outline: its rectangle eaten away by a ragged, slowly
// creeping char line, deepest along the bottom where the fire burns. Lengths
// are in CSS pixels.
const STEP = 5;
const KNOTS = 48;

export default class BurntEdge {
  constructor() {
    this.coarse = Array.from({ length: KNOTS }, Math.random);
    this.fine = Array.from({ length: KNOTS * 4 }, Math.random);
  }

  // Walks the card clockwise from its top-left corner. Each point's `low` runs from 0 at the top
  // of the card to 1 at the bottom, which is where the fire takes hold.
  trace(width, height, { time = 0, heat = 1 } = {}) {
    const perimeter = 2 * (width + height);
    const depth = (s, y) => {
      const ragged =
        sample(this.coarse, s + time * 0.004) * 0.65 +
        sample(this.fine, s - time * 0.012) * 0.35;
      const low = (y / height) ** 2;
      return (2 + ragged * 7 + low * (6 + ragged * 16)) * (0.85 + 0.15 * heat);
    };
    const sides = [
      { from: [0, 0], dir: [1, 0], normal: [0, 1], length: width },
      { from: [width, 0], dir: [0, 1], normal: [-1, 0], length: height },
      { from: [width, height], dir: [-1, 0], normal: [0, -1], length: width },
      { from: [0, height], dir: [0, -1], normal: [1, 0], length: height },
    ];
    // Each corner is burnt as deep as the edges meeting there, so neighbouring sides join up
    // instead of crossing into spikes.
    let walked = 0;
    const corners = sides.map(({ from, length }) => {
      const cut = depth(walked / perimeter, from[1]);
      walked += length;
      return cut;
    });
    const points = [];
    walked = 0;
    sides.forEach(({ from, dir, normal, length }, i) => {
      const start = corners[i];
      const end = length - corners[(i + 1) % sides.length];
      for (let t = start; t < end; t += STEP) {
        const x = from[0] + dir[0] * t;
        const y = from[1] + dir[1] * t;
        const cut = depth((walked + t) / perimeter, y);
        points.push({
          x: x + normal[0] * cut,
          y: y + normal[1] * cut,
          low: (y / height) ** 2,
        });
      }
      walked += length;
    });
    return points;
  }
}

// Smooth, looping noise: `s` wraps around the card, so the outline closes without a seam.
function sample(knots, s) {
  const n = knots.length;
  const f = (((s % 1) + 1) % 1) * n;
  const i = Math.floor(f);
  const ease = (1 - Math.cos(Math.PI * (f - i))) / 2;
  return knots[i] + (knots[(i + 1) % n] - knots[i]) * ease;
}
