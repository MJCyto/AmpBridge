import "phoenix_html"
import "../css/app.css"
import Alpine from 'alpinejs'
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

console.log("JavaScript loading...")

const VerticalSliderHook = {
  mounted() {
    this.el.addEventListener('input', (e) => {
      this.pushEvent('update_output_control', {
        volume: e.target.value,
        device_id: this.el.getAttribute('phx-value-device_id'),
        output_index: this.el.getAttribute('phx-value-output_index')
      });
    });
  }
};

const EthernetDiagramHook = {
  mounted() {
    console.log('EthernetDiagramHook mounted');
  }
};

const FileUploadHook = {
  mounted() {
    this.el.addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (file) {
        // Get the event name from phx-value-event attribute
        const eventName = this.el.getAttribute('phx-value-event');
        if (eventName) {
          // Read file content as text
          const reader = new FileReader();
          reader.onload = (event) => {
            const content = event.target.result;
            // Push the file content to the LiveView
            this.pushEvent(eventName, {content: content, filename: file.name});
          };
          reader.onerror = () => {
            console.error('Error reading file');
            this.pushEvent(eventName, {error: 'Failed to read file'});
          };
          reader.readAsText(file);
        }
      }
    });
  }
};

window.VerticalSliderHook = VerticalSliderHook;
window.EthernetDiagramHook = EthernetDiagramHook;
window.FileUploadHook = FileUploadHook;

console.log("Hooks registered immediately:", {
  VerticalSliderHook: !!window.VerticalSliderHook,
  EthernetDiagramHook: !!window.EthernetDiagramHook,
  FileUploadHook: !!window.FileUploadHook
});

try {
  let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
  console.log("CSRF Token:", csrfToken)
  
  let liveSocket = new LiveSocket("/live", Socket, {
    params: {_csrf_token: csrfToken},
    hooks: {
      VerticalSliderHook: VerticalSliderHook,
      EthernetDiagramHook: EthernetDiagramHook,
      FileUploadHook: FileUploadHook
    }
  })
  console.log("LiveSocket created:", liveSocket)
  
  console.log("Attempting to connect LiveSocket...")
  liveSocket.connect()
  console.log("LiveSocket connect called")
  
  window.liveSocket = liveSocket
  if (liveSocket.socket) {
    liveSocket.socket.onOpen(() => {
      console.log("LiveSocket opened!")
    })
    
    liveSocket.socket.onError((error) => {
      console.error("LiveSocket error:", error)
    })
    
    liveSocket.socket.onClose((event) => {
      console.log("LiveSocket closed:", event)
    })
  }
  
  console.log("LiveView setup completed successfully")
} catch (error) {
  console.error("Error setting up LiveView:", error)
}


window.Alpine = Alpine

Alpine.store('modal', {
  deviceTypesOpen: false
})

Alpine.start()

// Handle file downloads from LiveView events
const handleDownloadFile = (e) => {
  const { content, filename, content_type } = e.detail;
  
  if (!content || !filename) {
    return;
  }
  
  // Create a blob from the content
  const blob = new Blob([content], { type: content_type || "application/json" });
  
  // Create a temporary URL for the blob
  const url = window.URL.createObjectURL(blob);
  
  // Create a temporary anchor element and trigger download
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.style.display = "none";
  document.body.appendChild(a);
  a.click();
  
  // Clean up
  setTimeout(() => {
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
  }, 100);
};

// Listen for download_file events on document (events bubble from LiveView/LiveComponent)
document.addEventListener("phx:download_file", handleDownloadFile);

// Force scrollbar repaint to ensure transparent backgrounds are applied
document.addEventListener('DOMContentLoaded', function() {
  // Force repaint by temporarily hiding and showing the body
  document.body.style.display = 'none';
  document.body.offsetHeight; // Trigger reflow
  document.body.style.display = '';
  
  // Add loaded class to show body
  document.body.classList.add('loaded');
  
  // Additional scrollbar force repaint
  setTimeout(() => {
    const elements = document.querySelectorAll('*');
    elements.forEach(el => {
      if (el.scrollHeight > el.clientHeight || el.scrollWidth > el.clientWidth) {
        el.style.transform = 'translateZ(0)';
        el.offsetHeight; // Force reflow
        el.style.transform = '';
      }
    });
  }, 100);
});
