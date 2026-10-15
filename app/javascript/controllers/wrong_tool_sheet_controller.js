import { Controller } from "@hotwired/stimulus";

// wrong tool's feed ad (Feed::WrongToolPromoComponent): a rocket made of cells
// flies through cell stars. It dodges on its own; point at a row to steer it.
// Runs only while the ad's on screen, holds still for reduced motion, and stays
// gone once you hide it.
const HIDDEN_KEY = "wrong-tool-promo-hidden";
const TICK = 160;
const STAR_CHANCE = 0.3;
const NOSE = 4; // the rocket's nose column (E); its body trails behind it
const LOOKAHEAD = 3;

export default class extends Controller {
  static targets = ["cell", "nameBox"];
  static values = { columns: Number };

  connect() {
    if (this.#read(HIDDEN_KEY)) {
      this.element.hidden = true;
      return;
    }

    this.rows = this.cellTargets.length / this.columnsValue;
    this.row = Math.floor(this.rows / 2);
    this.steerRow = null;
    this.stars = [];
    this.hitTicks = 0;
    this.frame = 0;

    // A sky to start with, so even a still frame looks like the game.
    for (let column = 0; column < this.columnsValue; column += 2) {
      this.stars.push({ column, row: this.#randomRow() });
    }
    this.#draw();

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    this.observer = new IntersectionObserver(([entry]) =>
      entry.isIntersecting ? this.#start() : this.#stop(),
    );
    this.observer.observe(this.element);
  }

  disconnect() {
    this.#stop();
    this.observer?.disconnect();
  }

  steer(event) {
    const sheet = event.currentTarget.getBoundingClientRect();
    const firstCell = this.cellTargets[0].getBoundingClientRect();
    const row = Math.floor(
      ((event.clientY - firstCell.top) / (sheet.bottom - firstCell.top)) *
        this.rows,
    );
    this.steerRow = this.#clampRow(row);
  }

  release() {
    this.steerRow = null;
  }

  hide() {
    this.#write(HIDDEN_KEY, "1");
    this.element.hidden = true;
    this.disconnect();
  }

  #start() {
    this.timer ??= setInterval(() => this.#tick(), TICK);
  }

  #stop() {
    clearInterval(this.timer);
    this.timer = null;
  }

  #tick() {
    this.frame += 1;
    this.stars = this.stars
      .map((star) => ({ ...star, column: star.column - 1 }))
      .filter((star) => star.column >= 0);
    if (Math.random() < STAR_CHANCE)
      this.stars.push({
        column: this.columnsValue - 1,
        row: this.#randomRow(),
      });

    const goal = this.steerRow ?? this.#dodge();
    this.row += Math.sign(goal - this.row);

    const rocket = new Set(
      this.#rocketCells().map(({ column, row }) => `${column},${row}`),
    );
    const crashed = this.stars.filter((star) =>
      rocket.has(`${star.column},${star.row}`),
    );
    if (crashed.length) {
      this.stars = this.stars.filter((star) => !crashed.includes(star));
      this.hitTicks = 3;
    } else if (this.hitTicks) {
      this.hitTicks -= 1;
    }

    this.#draw();
  }

  // Steering itself: if a star's coming down this row, slide to whichever
  // neighbouring row is clearer.
  #dodge() {
    const danger = (row) =>
      this.stars.filter(
        (star) =>
          star.row === row &&
          star.column > NOSE &&
          star.column <= NOSE + LOOKAHEAD,
      ).length;
    if (!danger(this.row)) return this.row;

    const options = [this.row - 1, this.row + 1].filter(
      (row) => row === this.#clampRow(row),
    );
    return options.sort((a, b) => danger(a) - danger(b))[0] ?? this.row;
  }

  #rocketCells() {
    return [
      { column: NOSE, row: this.row, part: "nose" },
      { column: NOSE - 1, row: this.row, part: "rocket" },
      { column: NOSE - 2, row: this.row, part: "rocket" },
      { column: NOSE - 2, row: this.row - 1, part: "rocket" },
      { column: NOSE - 2, row: this.row + 1, part: "rocket" },
      ...(this.frame % 2
        ? []
        : [{ column: NOSE - 3, row: this.row, part: "flame" }]),
    ];
  }

  #draw() {
    this.cellTargets.forEach(
      (cell) => (cell.className = "wrong-tool-promo__cell"),
    );
    this.stars.forEach(({ column, row }) =>
      this.#cell(column, row)?.classList.add("wrong-tool-promo__cell--star"),
    );
    this.#rocketCells().forEach(({ column, row, part }) => {
      const modifier = this.hitTicks && part !== "flame" ? "hit" : part;
      this.#cell(column, row)?.classList.add(
        `wrong-tool-promo__cell--${modifier}`,
      );
    });
    this.nameBoxTarget.textContent = `${String.fromCharCode(65 + NOSE)}${this.row + 1}`;
  }

  #cell(column, row) {
    return this.cellTargets[row * this.columnsValue + column];
  }

  // The fins sit a row above and below the body, so it never touches the edges.
  #clampRow(row) {
    return Math.min(Math.max(row, 1), this.rows - 2);
  }

  #randomRow() {
    return Math.floor(Math.random() * this.rows);
  }

  #read(key) {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  #write(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch {
      // Private mode and the like: it's hidden for this page, at least.
    }
  }
}
