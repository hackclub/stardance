import { createConsumer } from "@rails/actioncable";
import { Howl } from "howler";

const consumer = createConsumer();

consumer.subscriptions.create("SiteActionsChannel", {
  received(data) {
    if (data.type === "audio_play" && data.file) {
      new Howl({ src: [data.file], html5: true }).play();
    }
  },
});
