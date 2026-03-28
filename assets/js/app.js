import "../css/app.css";

import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import createTopbar from "../vendor/topbar.js";
import Alpine from "alpinejs";

const FileUploadHook = {
  mounted() {
    this._onChange = (e) => {
      const file = e.target.files && e.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        this.pushEvent("import_commands", { content: reader.result });
        e.target.value = "";
      };
      reader.onerror = () => {
        this.pushEvent("import_commands", { error: "Failed to read file" });
        e.target.value = "";
      };
      reader.readAsText(file);
    };
    this.el.addEventListener("change", this._onChange);
  },
  destroyed() {
    this.el.removeEventListener("change", this._onChange);
  },
};

const csrfMeta = document.querySelector("meta[name='csrf-token']");
const csrfToken = csrfMeta ? csrfMeta.getAttribute("content") || "" : "";

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { FileUploadHook },
  dom: {
    onBeforeElUpdated(from, to) {
      if (from._x_dataStack && typeof Alpine.clone === "function") {
        Alpine.clone(from, to);
      }
    },
  },
});

const topbar = createTopbar({
  barColors: { 0: "#29d" },
  shadowColor: "rgba(0, 0, 0, .3)",
});
window.addEventListener("phx:page-loading-start", () => topbar.show(300));
window.addEventListener("phx:page-loading-stop", () => topbar.hide());

window.Alpine = Alpine;
Alpine.start();

liveSocket.connect();

window.liveSocket = liveSocket;
