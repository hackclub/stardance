import "@hotwired/turbo-rails";
import "./channels/site_actions_channel";
import { Turbo } from "@hotwired/turbo-rails";
import "chartkick/chart.js";
import { Chart, registerables } from "chart.js";
import "./controllers";
import * as ActiveStorage from "@rails/activestorage";

Turbo.session.drive = false;
Chart.register(...registerables);
window.Chart = Chart;

ActiveStorage.start();
