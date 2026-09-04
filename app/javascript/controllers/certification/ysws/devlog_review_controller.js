import { Controller } from "@hotwired/stimulus";

// Handles real-time updates for devlog review decisions in the admin review page.
// Each devlog item gets its own controller instance.
//
// Values:
//   - id: DevlogReview ID
//   - originalMinutes: Original minutes logged
//   - status: Current review status (pending/approved/rejected)
//
// Targets:
//   - panel: The review decision panel (for background color changes)
//   - minutesInput: The approved minutes input field
//   - approveButton: The approve button
//   - rejectButton: The reject button
//   - notesTextarea: The internal notes textarea
//
// Actions:
//   - updateMinutes: Saves minutes when input changes (debounced)
//   - approve: Approves the devlog
//   - reject: Rejects the devlog
//   - updateNotes: Saves notes when textarea changes (debounced)
//   - quickAdjust: Handles quick adjust buttons (50%, 25%, -30min, -1hr, Reset)

export default class extends Controller {
  static targets = [
    "panel",
    "minutesInput",
    "approveButton",
    "rejectButton",
    "notesTextarea",
    "hoursDisplay",
  ];

  static values = {
    id: Number,
    originalMinutes: Number,
    status: String,
  };

  connect() {
    //console.log(`DevlogReview #${this.idValue} controller connected!`);

    // Debounce timers
    this.minutesDebounceTimer = null;
    this.notesDebounceTimer = null;

    // Set initial visual state
    this.updateVisualState(this.statusValue);

    // Saved notes should render at full height, not just after a keystroke
    this.autogrow();
  }

  disconnect() {
    // Clear any pending debounce timers
    if (this.minutesDebounceTimer) clearTimeout(this.minutesDebounceTimer);
    if (this.notesDebounceTimer) clearTimeout(this.notesDebounceTimer);
  }

  // Update approved minutes (debounced)
  updateMinutes(event) {
    const minutes = parseInt(event.target.value, 10);

    // Ignore invalid numeric input so we do not send NaN/null to the server
    if (Number.isNaN(minutes)) {
      if (this.minutesDebounceTimer) clearTimeout(this.minutesDebounceTimer);
      return;
    }

    // Client-side validation: no negative minutes
    if (minutes < 0) {
      console.warn(
        `DevlogReview #${this.idValue}: Cannot set negative minutes`,
      );
      event.target.value = 0;
      return;
    }

    this.updateHoursDisplay(minutes);

    // Clear existing timer
    if (this.minutesDebounceTimer) clearTimeout(this.minutesDebounceTimer);

    // Debounce for 500ms
    this.minutesDebounceTimer = setTimeout(() => {
      // console.log(`DevlogReview #${this.idValue}: Updating minutes to ${minutes}`);
      this.sendUpdate({ approved_minutes: minutes });
    }, 500);
  }

  // Approve the devlog
  approve() {
    const minutes = parseInt(this.minutesInputTarget.value, 10);

    // Validate numeric input
    if (Number.isNaN(minutes)) {
      alert("Please enter a valid number for minutes");
      return;
    }

    if (minutes < 0) {
      alert("Cannot approve with negative minutes");
      return;
    }

    // console.log(`DevlogReview #${this.idValue}: Approving with ${minutes} minutes`);
    this.sendUpdate({
      status: "approved",
      approved_minutes: minutes,
    });
  }

  // Reject the devlog
  reject() {
    //console.log(`DevlogReview #${this.idValue}: Rejecting`);
    this.sendUpdate({
      status: "rejected",
      approved_minutes: 0,
    });
  }

  // Update internal notes (debounced)
  updateNotes(event) {
    const notes = event.target.value;

    // Update border color immediately — it depends on notes being non-empty
    this.updateVisualState(this.statusValue);

    // Clear existing timer
    if (this.notesDebounceTimer) clearTimeout(this.notesDebounceTimer);

    // Debounce for 1000ms (longer for text input)
    this.notesDebounceTimer = setTimeout(() => {
      //console.log(`DevlogReview #${this.idValue}: Updating notes`);
      this.sendUpdate({ justification: notes });
    }, 1000);
  }

  // Handle quick adjust buttons
  // Sends any debounced edit straight away instead of waiting its timer out, and
  // hands the in-flight request back through event.detail.pending. The review
  // flow awaits those before it submits, so a justification typed a moment
  // earlier can't be missed by the server's completion checks.
  //
  // The timer handles are never cleared once they fire, so a card the reviewer
  // touched at any point re-sends its current field values here even when
  // nothing is actually outstanding. That is deliberate: the resend carries
  // exactly what is on screen, Rails issues no UPDATE when nothing changed, and
  // all the cards flush concurrently — so over-sending costs a round trip, while
  // under-sending would lose a justification.
  flush(event) {
    const pending = event?.detail?.pending;
    const collect = (save) => {
      if (pending) pending.push(save);
    };

    if (this.minutesDebounceTimer) {
      clearTimeout(this.minutesDebounceTimer);
      this.minutesDebounceTimer = null;

      const minutes = parseInt(this.minutesInputTarget.value, 10);
      if (!Number.isNaN(minutes) && minutes >= 0) {
        collect(this.sendUpdate({ approved_minutes: minutes }));
      }
    }

    if (this.notesDebounceTimer) {
      clearTimeout(this.notesDebounceTimer);
      this.notesDebounceTimer = null;
      collect(
        this.sendUpdate({ justification: this.notesTextareaTarget.value }),
      );
    }
  }

  // Grow the notes textarea to fit its content so long justifications aren't
  // trapped behind an inner scrollbar. CSS min-height sets the floor.
  autogrow() {
    const el = this.notesTextareaTarget;

    el.style.height = "auto";
    // scrollHeight covers content + padding but not the border, and textareas
    // are border-box here, so add the border back or the last line clips.
    const border = el.offsetHeight - el.clientHeight;
    el.style.height = `${el.scrollHeight + border}px`;
  }

  quickAdjust(event) {
    const action = event.target.dataset.adjustAction;
    const parsed = parseInt(this.minutesInputTarget.value, 10);
    const currentMinutes = Number.isNaN(parsed)
      ? this.originalMinutesValue
      : parsed;
    let newMinutes;

    switch (action) {
      case "50%":
        newMinutes = Math.round(currentMinutes * 0.5);
        break;
      case "25%":
        newMinutes = Math.round(currentMinutes * 0.25);
        break;
      case "-15":
        newMinutes = Math.max(0, currentMinutes - 15);
        break;
      case "-30":
        newMinutes = Math.max(0, currentMinutes - 30);
        break;
      case "-60":
        newMinutes = Math.max(0, currentMinutes - 60);
        break;
      case "reset":
        newMinutes = this.originalMinutesValue;
        break;
      default:
        console.warn(`Unknown quick adjust action: ${action}`);
        return;
    }

    //console.log(`DevlogReview #${this.idValue}: Quick adjust ${action} - ${currentMinutes} → ${newMinutes} minutes`);

    // Update the input field and hours display
    this.minutesInputTarget.value = newMinutes;
    this.updateHoursDisplay(newMinutes);

    // Send update immediately (no debounce for button clicks)
    this.sendUpdate({ approved_minutes: newMinutes });
  }

  updateHoursDisplay(minutes) {
    this.hoursDisplayTarget.textContent = `(${(minutes / 60).toFixed(1)}h)`;
  }

  // Send update to server
  async sendUpdate(data) {
    const url = `/admin/certification/devlog_reviews/${this.idValue}`;
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]',
    )?.content;

    try {
      const response = await fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
        },
        body: JSON.stringify({ devlog_review: data }),
      });

      const result = await response.json();

      if (result.success) {
        //console.log(`DevlogReview #${this.idValue}: Update successful`, result.devlog_review);

        // Update visual state if status changed
        if (data.status) {
          this.statusValue = data.status;
          this.updateVisualState(data.status);
        }

        // Update input field and hours display if minutes were changed
        if (data.approved_minutes !== undefined) {
          this.minutesInputTarget.value = data.approved_minutes;
          this.updateHoursDisplay(data.approved_minutes);
        }

        // The Time Stats card is server-rendered and this endpoint answers with
        // JSON, so it can't know a decision changed unless we say so. Dispatched
        // last, once the status value and input hold the saved state.
        this.dispatch("saved", { prefix: "devlog-review" });
      } else {
        console.error(
          `DevlogReview #${this.idValue}: Update failed`,
          result.errors,
        );
        alert(`Update failed: ${result.errors.join(", ")}`);
      }
    } catch (error) {
      console.error(`DevlogReview #${this.idValue}: Network error`, error);
      alert("Network error. Please check your connection and try again.");
    }
  }

  // Update visual state based on status
  updateVisualState(status) {
    const hasNotes = this.notesTextareaTarget.value.trim().length > 0;

    this.panelTarget.classList.remove("approved", "rejected", "pending");
    this.approveButtonTarget.classList.remove("active");
    this.rejectButtonTarget.classList.remove("active");

    switch (status) {
      case "approved":
        // Approved devlogs don't individually require a justification (only at
        // least one approved devlog across the review must have one), so always
        // mark them complete.
        this.panelTarget.classList.add("approved");
        this.approveButtonTarget.classList.add("active");
        break;
      case "rejected":
        // Every rejected devlog needs its own justification, so only mark it
        // complete once notes are present.
        if (hasNotes) this.panelTarget.classList.add("rejected");
        this.rejectButtonTarget.classList.add("active");
        break;
      case "pending":
        this.panelTarget.classList.add("pending");
        break;
    }
  }
}
