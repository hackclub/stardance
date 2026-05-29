import { createConsumer } from "@rails/actioncable";

console.log("[SiteActions] module loaded");

const consumer = createConsumer();

consumer.subscriptions.create("SiteActionsChannel", {
  connected() {
    console.log("[SiteActions] connected");
  },
  disconnected() {
    console.log("[SiteActions] disconnected");
  },
  received(data) {
    console.log("[SiteActions] received", data);
    if (data.type === "audio_play" && data.file) {
      console.log("[SiteActions] playing audio:", data.file);
      import("howler").then(({ Howl }) => {
        const sound = new Howl({ src: [data.file], html5: true });
        sound.on("loaderror", (id, err) => console.error("[SiteActions] load error", err));
        sound.on("playerror", (id, err) => console.error("[SiteActions] play error", err));
        sound.play();
      }).catch(err => console.error("[SiteActions] failed to load howler", err));
    } else {
      console.warn("[SiteActions] unhandled message", data);
    }
  },
});
