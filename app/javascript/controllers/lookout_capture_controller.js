import { Controller } from "@hotwired/stimulus";

// Native Lookout recorder (the popup at /projects/:id/lookout_sessions/:id/record).
// Talks directly to Lookout's token-authenticated client API per
// https://github.com/hackclub/lookout/blob/main/docs/integration.md:
//   - Desktop: deep-link to the Lookout app, then poll status.
//   - Browser/Camera: grab a frame, GET upload-url, PUT it to R2, POST confirm,
//     then schedule the next capture from the server's nextExpectedAt (credit
//     mode). Time tracked = the server's trackedSeconds (we only display it).
const CLIENT_INFO = "Lookout Sdk (Stardance)/0.1.0 (web)";
const MAX_HEIGHT = 1080;
const TERMINAL = ["complete", "failed"];

export default class extends Controller {
  static targets = [
    "chooser",
    "desktopStage",
    "desktopStatus",
    "deepLink",
    "deepLinkText",
    "captureStage",
    "preview",
    "status",
    "timer",
    "pauseBtn",
    "resumeBtn",
    "stopBtn",
    "doneStage",
    "doneStatus",
    "result",
    "rendering",
    "destination",
    "existingSelect",
    "newName",
    "finishBtn",
    "destError",
    "postPrompt",
    "doneClose",
    "error",
  ];
  static values = {
    token: String,
    apiBase: String,
    deepLink: String,
    modeUrl: String,
    forwardUrl: String,
  };

  connect() {
    this.stream = null;
    this.captureTimer = null;
    this.displayTimer = null;
    this.statusTimer = null;
    this.paused = false;
    this.stopped = false;
    this.mode = null;
    this.baseSeconds = 0;
    this.lastSyncMs = Date.now();
  }

  disconnect() {
    this.cleanup();
  }

  // ── mode selection ────────────────────────────────────────────────────

  chooseDesktop() {
    this.mode = "desktop";
    this.setMode("desktop");
    this.showStage("desktop");
    this.deepLinkTextTarget.textContent = this.deepLinkValue;
    this.deepLinkTarget.href = this.deepLinkValue;
    window.location.href = this.deepLinkValue; // attempt to open the app
    this.setText(
      this.desktopStatusTarget,
      "Waiting for the Lookout app to start recording…",
    );
    // When the desktop app finishes, drop into the same done stage (preview +
    // "where should this time go?") the browser/camera flows use.
    this.pollStatus(this.desktopStatusTarget, {
      showVideo: true,
      doneOnComplete: true,
    });
  }

  async chooseBrowser() {
    this.mode = "web";
    this.setMode("web");
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: 1 },
        audio: false,
      });
      this.startCapture(stream, "Sharing your screen");
    } catch (_) {
      this.showError("Screen sharing was cancelled or blocked.");
    }
  }

  async chooseCamera() {
    this.mode = "camera";
    this.setMode("camera");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: true,
        audio: false,
      });
      this.startCapture(stream, "Recording from your webcam");
    } catch (_) {
      this.showError(
        "Couldn't access your webcam. Check your browser permissions.",
      );
    }
  }

  // ── capture loop ──────────────────────────────────────────────────────

  startCapture(stream, label) {
    this.stream = stream;
    this.showStage("capture");
    this.previewTarget.srcObject = stream;
    this.previewTarget.play().catch(() => {});

    // If the user ends the share from the browser's own UI, treat it as Stop.
    const track = stream.getVideoTracks()[0];
    if (track) track.addEventListener("ended", () => this.stop());

    this.paused = false;
    this.togglePauseButtons();
    this.setStatus(label);
    this.startDisplayTimer();
    this.tick();
  }

  async tick() {
    if (this.paused || this.stopped) return;

    const canvas = this.captureFrame();
    if (!canvas) {
      this.scheduleNext(2000); // video not ready yet
      return;
    }

    const capturedAt = new Date().toISOString();
    try {
      const blob = await new Promise((r) =>
        canvas.toBlob(r, "image/jpeg", 0.7),
      );
      if (!blob) throw new Error("Could not encode frame");

      const meta = await this.getJson(
        `/api/sessions/${this.tokenValue}/upload-url` +
          `?capturedAt=${encodeURIComponent(capturedAt)}` +
          `&clientInfo=${encodeURIComponent(CLIENT_INFO)}`,
      );
      await this.put(meta.uploadUrl, blob);
      const confirm = await this.postJson(
        `/api/sessions/${this.tokenValue}/screenshots`,
        {
          screenshotId: meta.screenshotId,
          width: canvas.width,
          height: canvas.height,
          fileSize: blob.size,
        },
      );

      const tracked = confirm.trackedSeconds ?? confirm.tracked_seconds;
      if (typeof tracked === "number") this.onTracked(tracked);
      this.setStatus("Recording…");

      const nextAt = confirm.nextExpectedAt || meta.nextExpectedAt;
      const delay = nextAt
        ? Math.max(0, new Date(nextAt).getTime() - Date.now())
        : 60000;
      this.scheduleNext(delay);
    } catch (error) {
      console.error("Lookout capture error", error);
      this.setStatus("Reconnecting…");
      this.scheduleNext(8000); // back off, then re-capture
    }
  }

  captureFrame() {
    const video = this.previewTarget;
    if (!video.videoWidth || !video.videoHeight) return null;
    const scale = Math.min(1, MAX_HEIGHT / video.videoHeight);
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  scheduleNext(delay) {
    this.clearTimer("captureTimer");
    if (this.stopped) return;
    this.captureTimer = setTimeout(() => this.tick(), delay);
  }

  // ── pause / resume / stop ─────────────────────────────────────────────

  async pause() {
    this.paused = true;
    this.clearTimer("captureTimer");
    this.togglePauseButtons();
    this.setStatus("Paused");
    await this.postJson(`/api/sessions/${this.tokenValue}/pause`, {}).catch(
      () => {},
    );
  }

  async resume() {
    this.paused = false;
    this.togglePauseButtons();
    this.setStatus("Recording…");
    await this.postJson(`/api/sessions/${this.tokenValue}/resume`, {}).catch(
      () => {},
    );
    this.lastSyncMs = Date.now();
    this.scheduleNext(0);
  }

  async stop() {
    if (this.stopped) return;
    this.stopped = true;
    this.clearTimer("captureTimer");
    this.clearTimer("displayTimer");
    this.stopStream();

    this.showStage("done");
    this.setText(this.doneStatusTarget, "Saving your recording…");
    this.chooseDestination(); // enable the right destination field for the default
    await this.postJson(`/api/sessions/${this.tokenValue}/stop`, {}).catch(
      () => {},
    );
    // No auto-forward: the user picks where the time goes (or not) on this stage,
    // then clicks Finish. Meanwhile, poll for the compiled video to preview it.
    this.pollStatus(this.doneStatusTarget, { showVideo: true });
  }

  // Persist how this session is being recorded so the forwarded heartbeats get
  // tagged Lookout-Desktop / Lookout-Web / Lookout-Camera. Best-effort.
  setMode(mode) {
    if (!this.modeUrlValue) return;
    fetch(this.modeUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
      },
      body: JSON.stringify({ mode }),
    }).catch(() => {});
  }

  // ── destination ("where should this time go?") ────────────────────────

  // Enable only the input that belongs to the currently-selected destination,
  // and clear any prior validation error.
  chooseDestination() {
    const choice = this.selectedDestination();
    if (this.hasExistingSelectTarget)
      this.existingSelectTarget.disabled = choice !== "existing";
    if (this.hasNewNameTarget) this.newNameTarget.disabled = choice !== "new";
    if (this.hasDestErrorTarget) this.destErrorTarget.hidden = true;
  }

  selectedDestination() {
    const checked = this.element.querySelector(
      'input[name="lookout-dest"]:checked',
    );
    return checked ? checked.value : "skip";
  }

  // Confirm the destination: forward the captured time to the chosen Hackatime
  // project (existing or new), or send nothing when the user opted out.
  async finish() {
    const choice = this.selectedDestination();
    let projectName = null;
    if (choice === "existing")
      projectName = this.hasExistingSelectTarget
        ? this.existingSelectTarget.value
        : "";
    else if (choice === "new")
      projectName = this.hasNewNameTarget
        ? this.newNameTarget.value.trim()
        : "";

    if ((choice === "existing" || choice === "new") && !projectName) {
      this.showDestError(
        choice === "existing"
          ? "Pick a Hackatime project to send your time to."
          : "Enter a name for the new Hackatime project.",
      );
      return;
    }

    if (this.hasFinishBtnTarget) this.finishBtnTarget.disabled = true;

    if (projectName) {
      this.setText(this.doneStatusTarget, "Sending your time to Hackatime…");
      try {
        await this.forwardHeartbeats(projectName);
        this.setText(
          this.doneStatusTarget,
          `Time sent to “${projectName}” — it'll show up in Hackatime shortly.`,
        );
      } catch (error) {
        // Surface the real reason next to the button and let the user retry,
        // instead of advancing as though the time was sent.
        console.error("Lookout forward error", error);
        this.setText(this.doneStatusTarget, "Your timelapse is saved.");
        this.showDestError(
          error.message ||
            "We couldn't send your time to Hackatime — please try again.",
        );
        if (this.hasFinishBtnTarget) this.finishBtnTarget.disabled = false;
        return;
      }
    } else {
      this.setText(
        this.doneStatusTarget,
        "All done — your recording was saved without sending time.",
      );
    }

    if (this.hasDestinationTarget) this.destinationTarget.hidden = true;
    // The time only counts toward the project once it's in a devlog — nudge the
    // user there, but only when we actually sent time.
    if (projectName && this.hasPostPromptTarget) {
      this.postPromptTarget.hidden = false;
    }
    if (this.hasDoneCloseTarget) this.doneCloseTarget.hidden = false;
  }

  showDestError(message) {
    if (!this.hasDestErrorTarget) return;
    this.destErrorTarget.textContent = message;
    this.destErrorTarget.hidden = false;
  }

  // Ask our backend to forward this session's capture timestamps to Hackatime
  // as heartbeats under `projectName` (it has the user's token server-side).
  async forwardHeartbeats(projectName) {
    if (!this.forwardUrlValue || !projectName) return;
    const res = await fetch(this.forwardUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        Accept: "application/json",
      },
      body: JSON.stringify({ project_name: projectName }),
    });
    if (!res.ok) throw new Error(await this.forwardError(res));
  }

  // Pull the server's user-facing explanation out of the error response so the
  // recorder shows *why* the send failed, not just a status code.
  async forwardError(res) {
    try {
      const body = await res.json();
      if (body && body.error) return body.error;
    } catch (_) {
      // non-JSON response
    }
    return `We couldn't send your time to Hackatime (error ${res.status}).`;
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
  }

  // ── status polling / completion ───────────────────────────────────────

  async pollStatus(
    statusEl,
    { showVideo = false, doneOnComplete = false } = {},
  ) {
    this.clearTimer("statusTimer");
    let data;
    try {
      data = await this.getJson(`/api/sessions/${this.tokenValue}/status`);
    } catch (_) {
      this.statusTimer = setTimeout(
        () => this.pollStatus(statusEl, { showVideo, doneOnComplete }),
        4000,
      );
      return;
    }

    if (data.status === "complete") {
      if (doneOnComplete) {
        this.showStage("done");
        this.chooseDestination();
        this.setText(this.doneStatusTarget, "Your timelapse is ready!");
      } else {
        this.setText(statusEl, "Your timelapse is ready!");
      }
      if (showVideo) await this.revealVideo();
      return;
    }
    if (data.status === "failed") {
      this.setText(
        doneOnComplete ? this.doneStatusTarget : statusEl,
        "That recording failed to process — you can try again.",
      );
      return;
    }

    this.setText(statusEl, "Processing your timelapse…");
    if (!TERMINAL.includes(data.status)) {
      this.statusTimer = setTimeout(
        () => this.pollStatus(statusEl, { showVideo, doneOnComplete }),
        4000,
      );
    }
  }

  // Embed the compiled timelapse so the user can preview it before deciding
  // where the time should go. Falls back to a "ready soon" note if not yet up.
  async revealVideo() {
    let url;
    try {
      const v = await this.getJson(`/api/sessions/${this.tokenValue}/video`);
      url = v.videoUrl || v.video_url || v.url;
    } catch (_) {
      /* video URL not ready; the session row still syncs server-side later */
    }

    if (url && this.hasResultTarget) {
      this.resultTarget.src = url;
      this.resultTarget.hidden = false;
      if (this.hasRenderingTarget) this.renderingTarget.hidden = true;
    } else if (this.hasRenderingTarget) {
      this.renderingTarget.textContent =
        "Your timelapse will be ready to watch in a moment.";
    }
  }

  close(event) {
    if (event) event.preventDefault();
    this.cleanup();
    window.close();
  }

  // ── helpers ───────────────────────────────────────────────────────────

  onTracked(seconds) {
    if (seconds > this.baseSeconds) {
      this.baseSeconds = seconds;
      this.lastSyncMs = Date.now();
    }
  }

  startDisplayTimer() {
    this.updateTimer();
    this.displayTimer = setInterval(() => this.updateTimer(), 1000);
  }

  updateTimer() {
    if (!this.hasTimerTarget) return;
    const elapsed = Math.max(
      0,
      Math.floor((Date.now() - this.lastSyncMs) / 1000),
    );
    this.timerTarget.textContent = this.formatTime(
      this.baseSeconds + Math.min(60, elapsed),
    );
  }

  formatTime(total) {
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    return h > 0 ? `${h}h ${m}m` : `${m}m ${s}s`;
  }

  togglePauseButtons() {
    if (this.hasPauseBtnTarget) this.pauseBtnTarget.hidden = this.paused;
    if (this.hasResumeBtnTarget) this.resumeBtnTarget.hidden = !this.paused;
  }

  showStage(stage) {
    this.chooserTarget.hidden = stage !== "chooser";
    if (this.hasDesktopStageTarget)
      this.desktopStageTarget.hidden = stage !== "desktop";
    if (this.hasCaptureStageTarget)
      this.captureStageTarget.hidden = stage !== "capture";
    if (this.hasDoneStageTarget) this.doneStageTarget.hidden = stage !== "done";
  }

  setStatus(text) {
    this.setText(this.hasStatusTarget ? this.statusTarget : null, text);
  }

  setText(el, text) {
    if (el) el.textContent = text;
  }

  showError(message) {
    if (!this.hasErrorTarget) return;
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
    this.showStage("chooser");
  }

  // ── Lookout client API (cross-origin, token-authenticated) ────────────

  url(path) {
    return `${this.apiBaseValue}${path}`;
  }

  async getJson(path) {
    const res = await fetch(this.url(path), {
      headers: { Accept: "application/json" },
    });
    if (!res.ok) throw new Error(`GET ${path} -> ${res.status}`);
    return res.json();
  }

  async postJson(path, body) {
    const res = await fetch(this.url(path), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`POST ${path} -> ${res.status}`);
    return res.json().catch(() => ({}));
  }

  async put(uploadUrl, blob) {
    const res = await fetch(uploadUrl, {
      method: "PUT",
      body: blob,
      headers: { "Content-Type": "image/jpeg" },
    });
    if (!res.ok) throw new Error(`PUT screenshot -> ${res.status}`);
  }

  // ── teardown ──────────────────────────────────────────────────────────

  stopStream() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop());
      this.stream = null;
    }
  }

  clearTimer(name) {
    if (this[name]) {
      clearTimeout(this[name]);
      clearInterval(this[name]);
      this[name] = null;
    }
  }

  cleanup() {
    this.stopped = true;
    this.clearTimer("captureTimer");
    this.clearTimer("displayTimer");
    this.clearTimer("statusTimer");
    this.stopStream();
  }
}
