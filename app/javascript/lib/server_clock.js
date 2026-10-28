// A server timestamp plus monotonic elapsed time. Never consult the OS clock.
export class ServerClock {
  constructor({
    fetchTime = () =>
      fetch("/server_time", {
        cache: "no-store",
        credentials: "same-origin",
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(5000),
      }),
    monotonic = () => performance.now(),
  } = {}) {
    this.fetchTime = fetchTime;
    this.monotonic = monotonic;
    this.anchor = null;
    this.listeners = new Set();
    this.resume = () => {
      if (document.hidden) return;
      // Some platforms pause performance.now() during sleep. Resync before
      // rendering or starting a finale when the page becomes visible again.
      this.anchor = null;
      this.sync();
    };
  }

  now() {
    return this.anchor
      ? this.anchor.server + this.monotonic() - this.anchor.local
      : NaN;
  }

  sync() {
    if (this.pending) return this.pending;
    this.pending = this.sample().finally(() => {
      this.pending = null;
    });
    return this.pending;
  }

  async sample() {
    const sentAt = this.monotonic();
    try {
      const response = await this.fetchTime();
      if (!response.ok) return null;
      const data = await response.json();
      const receivedAt = this.monotonic();
      const server = Date.parse(data.now);
      if (!Number.isFinite(server) || typeof data.ended !== "boolean")
        return null;
      // Approximate one-way latency using half of the round trip.
      this.anchor = {
        server: server + (receivedAt - sentAt) / 2,
        local: receivedAt,
      };
      this.listeners.forEach((listener) => listener());
      return data;
    } catch {
      // Retain a previous monotonic sample while offline, never fall back to
      // device time. A finale still requires a successful server confirmation.
      return null;
    }
  }

  subscribe(listener) {
    this.listeners.add(listener);
    if (this.listeners.size === 1) {
      this.timer = setInterval(() => {
        if (!document.hidden) this.sync();
      }, 30000);
      document.addEventListener("visibilitychange", this.resume);
      window.addEventListener("pageshow", this.resume);
      window.addEventListener("focus", this.resume);
      this.sync();
    }
    return () => {
      this.listeners.delete(listener);
      if (this.listeners.size) return;
      clearInterval(this.timer);
      document.removeEventListener("visibilitychange", this.resume);
      window.removeEventListener("pageshow", this.resume);
      window.removeEventListener("focus", this.resume);
    };
  }
}

export const serverClock = new ServerClock();
