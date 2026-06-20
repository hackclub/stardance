import { Controller } from "@hotwired/stimulus";

// data-controller="project-type"
// Toggles a project between software and hardware in the inline edit form.
// Hardware vs software is derived purely from hardware_stage (present =
// hardware), so this controller owns no field of its own — it drives the
// hardware_stage radios:
//   • Software → hide + disable the stage radios so they don't submit, leaving
//     the empty hidden hardware_stage field to clear the column.
//   • Hardware → reveal + enable the stage radios and ensure one is picked
//     (defaults to the first stage, "design").
export default class extends Controller {
  static targets = ["stageSection", "stageRadio", "typeRadio"];

  connect() {
    this.sync();
  }

  sync() {
    const hardware = this.isHardware();

    if (this.hasStageSectionTarget) {
      this.stageSectionTarget.hidden = !hardware;
    }

    this.stageRadioTargets.forEach((radio) => {
      radio.disabled = !hardware;
    });

    if (hardware && !this.stageRadioTargets.some((radio) => radio.checked)) {
      const first = this.stageRadioTargets[0];
      if (first) first.checked = true;
    }
  }

  isHardware() {
    const checked = this.typeRadioTargets.find((radio) => radio.checked);
    return checked ? checked.value === "hardware" : false;
  }
}
