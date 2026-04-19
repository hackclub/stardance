import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this._x = 0;
    this._y = 0;
    this._targetX = 0;
    this._targetY = 0;
    this._hovering = false;
    this._raf = null;
    this._alphaData = null;

    this._imgEl = this.element.querySelector(".prizes__item-img");
    if (this._imgEl) {
      if (this._imgEl.complete && this._imgEl.naturalWidth > 0) {
        this._buildAlphaMap();
      } else {
        this._imgEl.addEventListener("load", () => this._buildAlphaMap(), {
          once: true,
        });
      }
    }

    this.element.addEventListener("pointermove", this._onMove);
    this.element.addEventListener("pointerleave", this._onLeave);
  }

  disconnect() {
    this.element.removeEventListener("pointermove", this._onMove);
    this.element.removeEventListener("pointerleave", this._onLeave);
    cancelAnimationFrame(this._raf);
  }

  _buildAlphaMap() {
    const img = this._imgEl;
    const w = img.naturalWidth;
    const h = img.naturalHeight;
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    ctx.drawImage(img, 0, 0);
    try {
      this._alphaData = ctx.getImageData(0, 0, w, h).data;
    } catch {
      this._alphaData = null;
    }
    this._natW = w;
    this._natH = h;
  }

  _isOverOpaque(e) {
    if (!this._alphaData || !this._imgEl) return true;

    const rect = this.element.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;

    const style = getComputedStyle(this.element);
    const matrix = new DOMMatrix(style.transform);
    const inverse = matrix.inverse();

    const pt = inverse.transformPoint(
      new DOMPoint(e.clientX - cx, e.clientY - cy),
    );

    const origW = this.element.offsetWidth;
    const origH = this.element.offsetHeight;
    const localX = pt.x + origW / 2;
    const localY = pt.y + origH / 2;

    const imgX = Math.round((localX / this._imgEl.offsetWidth) * this._natW);
    const imgY = Math.round((localY / this._imgEl.offsetHeight) * this._natH);

    if (imgX < 0 || imgX >= this._natW || imgY < 0 || imgY >= this._natH)
      return false;

    const alpha = this._alphaData[(imgY * this._natW + imgX) * 4 + 3];
    return alpha > 20;
  }

  _onMove = (e) => {
    if (this._isOverOpaque(e)) {
      if (!this._hovering) {
        this._hovering = true;
        this._pickTarget();
        this._startLoop();
      }
    } else {
      if (this._hovering) {
        this._hovering = false;
        this._targetX = 0;
        this._targetY = 0;
      }
    }
  };

  _onLeave = () => {
    this._hovering = false;
    this._targetX = 0;
    this._targetY = 0;
  };

  _pickTarget() {
    this._targetX = (Math.random() - 0.5) * 40;
    this._targetY = (Math.random() - 0.5) * 40;
    this._nextPick = performance.now() + 500 + Math.random() * 1000;
  }

  _startLoop() {
    if (this._raf) return;
    const tick = (now) => {
      if (this._hovering && now >= this._nextPick) {
        this._pickTarget();
      }

      const ease = this._hovering ? 0.015 : 0.04;
      this._x += (this._targetX - this._x) * ease;
      this._y += (this._targetY - this._y) * ease;

      this.element.style.translate = `${this._x}px ${this._y}px`;

      if (
        !this._hovering &&
        Math.abs(this._x) < 0.1 &&
        Math.abs(this._y) < 0.1
      ) {
        this.element.style.translate = "";
        this._x = 0;
        this._y = 0;
        this._raf = null;
        return;
      }

      this._raf = requestAnimationFrame(tick);
    };
    this._raf = requestAnimationFrame(tick);
  }
}
