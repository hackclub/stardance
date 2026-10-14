import "@hotwired/turbo-rails";
import { Turbo } from "@hotwired/turbo-rails";
import "chartkick/chart.js";
import { Chart, registerables } from "chart.js";
import "./controllers";
import * as ActiveStorage from "@rails/activestorage";

Turbo.session.drive = false;
Chart.register(...registerables);
window.Chart = Chart;

ActiveStorage.start();

// Opens the "name your project" prompt for a create form. Falls back to
// submitting the form when <dialog> can't open, so creation degrades to a
// title validation error rather than doing nothing at all.
window.openNamePrompt = function (trigger, dialogId) {
  const dialog = document.getElementById(dialogId);
  if (dialog && typeof dialog.showModal === "function") {
    dialog.showModal();
    return;
  }
  trigger.form?.submit();
};
