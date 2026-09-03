// Transient flash messages for the YSWS admin review pages, which talk to the
// server over fetch and so can't rely on the server-rendered flash.
//
// complete_review_controller.js carries an identical private copy from before
// this module existed; it is deliberately left alone so this addon can't change
// the queue's own Complete Review button. Fold it in here when that button is
// next touched.
export function showFlash(message, variant = "error") {
  let container = document.querySelector(".flash-container");
  if (!container) {
    container = document.createElement("div");
    container.className = "flash-container";
    document.body.appendChild(container);
  }

  const el = document.createElement("div");
  el.className = `alert alert-${variant}`;
  el.setAttribute("role", "alert");
  el.setAttribute("aria-live", "assertive");
  el.setAttribute("data-controller", "flash");
  el.setAttribute("data-flash-timeout-value", "5000");

  // Built as nodes with textContent rather than innerHTML: these messages carry
  // raw exception text, and the Airtable client quotes the API response body
  // verbatim into its error — none of which should be parsed as markup.
  const content = document.createElement("div");
  content.className = "alert__content";
  content.textContent = message;

  const close = document.createElement("button");
  close.type = "button";
  close.className = "alert__close";
  close.setAttribute("aria-label", "Close");
  close.setAttribute("data-action", "click->flash#close");
  close.textContent = "×";

  el.append(content, close);
  container.appendChild(el);
}

export function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content;
}
