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

window.addEventListener("phx:copy_messages_to_console", async (event) => {
  const text = JSON.stringify(event.detail.messages, null, 2);
  console.log("=== SERIAL MESSAGE LOG DATA ===");
  console.log(text);
  console.log("=== END MESSAGE LOG DATA ===");
});

window.addEventListener("phx:copy_messages_to_clipboard", async (event) => {
  const text = JSON.stringify(event.detail.messages, null, 2);
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
    } else {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.focus();
      textarea.select();
      document.execCommand("copy");
      textarea.remove();
    }
  } catch (error) {
    console.warn("Could not copy serial message data to the clipboard", error);
  }
});

liveSocket.connect();

window.liveSocket = liveSocket;
