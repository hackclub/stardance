import "@videojs/html/video/player";
import "@videojs/html/video/minimal-skin";
import { MinimalVideoSkinElement } from "@videojs/html/video";

// Video.js's minimal video skin, trimmed for timelapse review. Adapted from the
// packaged template (@videojs/html internal/skins/minimal-video/template.js):
// volume, captions, settings, cast, AirPlay and picture-in-picture are gone,
// and a `speed` slot in the control bar takes the lapse player's JKL ladder.
// The skin's own styles are inherited unchanged.
//
// Hotkeys listen on the document: the skin only ever lives in the lapse
// player's modal lightbox, so it is the one player on the page while open.
// Space/k stay registered so tooltips show them, but the lapse player's
// capture-phase handler runs first and owns those keys (plus j/l and the
// arrows) for its JKL transport.
const template = document.createElement("template");
template.innerHTML = `
<media-container class="media-skin media-container video-skin" data-theme="minimal" data-preset="video">
  <slot></slot>
  <media-buffering-indicator class="media-buffering-indicator">
    <media-icon family="minimal" name="spinner" class="media-buffering-indicator-spinner-icon"></media-icon>
  </media-buffering-indicator>
  <media-error-dialog class="media-dialog-root">
    <media-dialog-backdrop class="media-dialog-backdrop"></media-dialog-backdrop>
    <media-dialog-popup class="media-dialog-popup">
      <div class="media-dialog-content">
        <media-dialog-title class="media-dialog-title"></media-dialog-title>
        <media-dialog-description class="media-dialog-description"></media-dialog-description>
      </div>
      <div class="media-dialog-actions">
        <media-dialog-close class="media-button media-dialog-close"></media-dialog-close>
      </div>
    </media-dialog-popup>
  </media-error-dialog>
  <media-controls>
    <media-controls-backdrop class="video-controls-backdrop"></media-controls-backdrop>
    <media-controls-content class="video-controls video-controls-content video-controls-wrap">
      <media-tooltip-group>
        <media-controls-group class="video-controls-start">
          <media-play-button class="media-button media-play-button" id="play-trigger">
            <media-icon family="minimal" name="restart" class="media-button-icon media-play-button-restart-icon"></media-icon>
            <media-icon family="minimal" name="play" class="media-button-icon media-play-button-play-icon"></media-icon>
            <media-icon family="minimal" name="pause" class="media-button-icon media-play-button-pause-icon"></media-icon>
          </media-play-button>
          <media-tooltip trigger="play-trigger" side="top" class="media-popup media-popup-safe-area media-popup-transition media-popup-surface media-tooltip">
            <media-tooltip-label></media-tooltip-label>
            <media-tooltip-shortcut class="media-tooltip-shortcut"></media-tooltip-shortcut>
          </media-tooltip>
        </media-controls-group>
        <media-controls-group class="video-time-slider-group">
          <media-time-group class="media-time-group">
            <media-time class="media-time-toggle media-time-current-value" type="current" toggle></media-time>
            <media-time-separator class="media-time-separator"></media-time-separator>
            <media-time class="media-time-duration-value" type="duration"></media-time>
          </media-time-group>
          <media-time-slider class="media-slider media-time-slider">
            <media-time-slider-chapters class="media-time-slider-chapters">
              <template>
                <div class="media-time-slider-chapter">
                  <media-slider-track class="media-slider-track media-time-slider-chapter-track">
                    <media-slider-buffer class="media-slider-buffer"></media-slider-buffer>
                    <media-slider-fill class="media-slider-fill"></media-slider-fill>
                  </media-slider-track>
                </div>
              </template>
            </media-time-slider-chapters>
            <media-slider-thumb class="media-slider-thumb media-time-slider-thumb"></media-slider-thumb>
            <media-slider-preview class="media-slider-preview" overflow="clamp">
              <div class="media-slider-preview-content media-time-slider-preview-content">
                <media-slider-value class="media-time-slider-value" type="pointer"></media-slider-value>
              </div>
            </media-slider-preview>
          </media-time-slider>
        </media-controls-group>
        <media-controls-group class="video-controls-end">
          <slot name="speed"></slot>
          <media-fullscreen-button class="media-button media-fullscreen-button" id="fullscreen-trigger">
            <media-icon family="minimal" name="fullscreen-enter" class="media-button-icon media-fullscreen-button-enter-icon"></media-icon>
            <media-icon family="minimal" name="fullscreen-exit" class="media-button-icon media-fullscreen-button-exit-icon"></media-icon>
          </media-fullscreen-button>
          <media-tooltip trigger="fullscreen-trigger" side="top" class="media-popup media-popup-safe-area media-popup-transition media-popup-surface media-tooltip">
            <media-tooltip-label></media-tooltip-label>
            <media-tooltip-shortcut class="media-tooltip-shortcut"></media-tooltip-shortcut>
          </media-tooltip>
        </media-controls-group>
      </media-tooltip-group>
    </media-controls-content>
  </media-controls>
  <media-hotkey keys="Space" action="togglePaused" target="document"></media-hotkey>
  <media-hotkey keys="k" action="togglePaused" target="document"></media-hotkey>
  <media-hotkey keys="0-9" action="seekToPercent" target="document"></media-hotkey>
  <media-hotkey keys="Home" action="seekToPercent" value="0" target="document"></media-hotkey>
  <media-hotkey keys="End" action="seekToPercent" value="100" target="document"></media-hotkey>
  <media-hotkey keys="f" action="toggleFullscreen" target="document"></media-hotkey>
  <media-gesture type="tap" action="togglePaused" pointer="mouse" region="center"></media-gesture>
  <media-gesture type="tap" action="toggleControls" pointer="touch"></media-gesture>
  <media-gesture type="doubletap" action="seekStep" region="left"></media-gesture>
  <media-gesture type="doubletap" action="toggleFullscreen" region="center"></media-gesture>
  <media-gesture type="doubletap" action="seekStep" region="right"></media-gesture>
  <media-status-announcer class="media-status-announcer"></media-status-announcer>
  <div class="video-status-indicators">
    <media-status-indicator actions="toggleFullscreen" class="media-indicator media-status-indicator">
      <div class="media-indicator-content media-status-indicator-content">
        <media-icon family="minimal" name="fullscreen-enter" class="media-status-indicator-fullscreen-enter-icon"></media-icon>
        <media-icon family="minimal" name="fullscreen-exit" class="media-status-indicator-fullscreen-exit-icon"></media-icon>
        <media-status-indicator-value class="media-status-indicator-value"></media-status-indicator-value>
      </div>
    </media-status-indicator>
    <media-seek-indicator class="media-seek-indicator">
      <media-icon family="minimal" name="chevron" class="media-seek-indicator-icon"></media-icon>
      <media-seek-indicator-value class="media-seek-indicator-value"></media-seek-indicator-value>
    </media-seek-indicator>
    <media-status-indicator actions="togglePaused" class="media-playback-status-indicator">
      <media-icon family="minimal" name="play" class="media-playback-status-indicator-play-icon"></media-icon>
      <media-icon family="minimal" name="pause" class="media-playback-status-indicator-pause-icon"></media-icon>
    </media-status-indicator>
  </div>
</media-container>`;

class LapsePlayerSkinElement extends MinimalVideoSkinElement {
  static tagName = "lapse-player-skin";
  static template = template;

  #slider = this.shadowRoot.querySelector("media-time-slider");
  #scrubTarget = null;

  connectedCallback() {
    super.connectedCallback();
    this.#slider.addEventListener("drag-start", this.#startScrub);
    this.#slider.addEventListener("drag-end", this.#endScrub);
  }

  disconnectedCallback() {
    this.#endScrub();
    this.#slider.removeEventListener("drag-start", this.#startScrub);
    this.#slider.removeEventListener("drag-end", this.#endScrub);
    super.disconnectedCallback();
  }

  // Live scrubbing: this version of the time slider only seeks when the drag
  // is released, so the frame follows the pointer here instead. A new seek
  // starts only once the previous one has landed (always to the latest pointer
  // position), so slow network seeks can't keep cancelling each other and
  // leave the frame frozen until release.
  #startScrub = () => {
    window.addEventListener("pointermove", this.#scrubTo);
    this.#video?.addEventListener("seeked", this.#seekPending);
  };

  #endScrub = () => {
    window.removeEventListener("pointermove", this.#scrubTo);
    this.#video?.removeEventListener("seeked", this.#seekPending);
    this.#scrubTarget = null;
  };

  #scrubTo = (event) => {
    const video = this.#video;
    if (!video?.duration) return;
    const rect = this.#slider.getBoundingClientRect();
    const percent = Math.min(
      1,
      Math.max(0, (event.clientX - rect.left) / rect.width),
    );
    this.#scrubTarget = percent * video.duration;
    if (!video.seeking) this.#seekPending();
  };

  #seekPending = () => {
    if (this.#scrubTarget == null || !this.#video) return;
    this.#video.currentTime = this.#scrubTarget;
    this.#scrubTarget = null;
  };

  get #video() {
    return this.querySelector("video");
  }
}

if (!customElements.get(LapsePlayerSkinElement.tagName))
  customElements.define(LapsePlayerSkinElement.tagName, LapsePlayerSkinElement);
