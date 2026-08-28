import { Controller } from "@hotwired/stimulus";
import { showFlash, csrfToken } from "./flash";

// Submit-and-advance for the continuous review flow.
//
// Only mounted while a review session is running; without one the page keeps the
// untouched complete-review controller. Pressing OK on the confirm is the last
// click a reviewer makes — the sync runs and the next project's page loads on its
// own, with no second button to press.
//
// URLs arrive as values so the Rails route helpers stay the single source of the
// paths rather than being restated here.
export default class extends Controller {
  static targets = ["button"];
  static values = { submitUrl: String, nextUrl: String };

  async submit(event) {
    event.preventDefault();

    if (
      !confirm(
        "Are you sure you want to complete this review? This will sync the review to Airtable and mark it as done.",
      )
    ) {
      return;
    }

    const button = this.buttonTarget;
    const label = button.textContent;
    button.disabled = true;
    button.textContent = "Completing...";

    try {
      await this.flushDevlogSaves();

      const response = await fetch(this.submitUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken(),
        },
      });

      // Not every failure answers in JSON: a pulled feature flag redirects to
      // the queue and fetch follows it, so the body can be an HTML page.
      const data = await response.json().catch(() => null);
      if (!data) {
        this.restore(button, label);
        showFlash(
          `The server gave an unexpected response (HTTP ${response.status}). Your review session may have ended — reload the queue.`,
          "error",
        );
        return;
      }

      if (!response.ok || !data.success) {
        this.restore(button, label);
        showFlash(data.error || "Failed to complete review", "error");
        return;
      }

      // reviewed_at is stamped whether or not Airtable answered, so this must
      // never re-submit. But an automatic navigation would tear the warning out
      // of the DOM before it could be read, and the reviewer is the only person
      // who can put it right — so an unconfirmed sync stops the ride here and
      // lets them move on deliberately.
      if (!data.synced) {
        showFlash(
          data.error ||
            "Airtable didn't confirm the sync. Use Resync on this review before moving on.",
          "error",
        );
        this.armContinue(button);
        return;
      }

      button.textContent = "Synced ✓";
      window.location.href = this.nextUrlValue;
    } catch (error) {
      console.error("Error completing review:", error);
      this.restore(button, label);
      showFlash("An unexpected error occurred. Please try again.", "error");
    }
  }

  // Devlog cards autosave on a debounce, so an edit made a moment ago can still
  // be in flight. Asking them to flush and awaiting whatever they hand back
  // keeps a just-typed justification from being missed by the server's
  // completion checks.
  async flushDevlogSaves() {
    const pending = [];
    this.dispatch("flush", {
      prefix: "devlog-review",
      target: window,
      detail: { pending },
    });
    await Promise.all(pending);
  }

  // The review is already closed, so the button must not submit again. Swapping
  // the action leaves a plain navigation behind and nothing else.
  armContinue(button) {
    button.disabled = false;
    button.textContent = "Sync failed — continue →";
    button.dataset.action =
      "click->certification--ysws--review-flow#continueToNext";
  }

  continueToNext(event) {
    event.preventDefault();
    window.location.href = this.nextUrlValue;
  }

  restore(button, label) {
    button.disabled = false;
    button.textContent = label;
  }
}
