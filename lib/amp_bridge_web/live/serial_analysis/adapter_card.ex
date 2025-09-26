defmodule AmpBridgeWeb.SerialAnalysis.AdapterCard do
  use Phoenix.Component

  attr(:adapter_name, :string, required: true)
  attr(:adapter_color, :string, required: true)
  attr(:connected, :boolean, default: false)
  attr(:device, :string, default: nil)
  attr(:available_devices, :list, default: [])
  attr(:settings, :map, default: %{})
  attr(:settings_changed, :boolean, default: false)
  attr(:adapter_key, :atom, required: true)
  attr(:show_advanced, :boolean, default: false)
  attr(:myself, :any, default: nil)

  def adapter_card(assigns) do
    ~H"""
    <div class="flex-1 bg-neutral-700 rounded-lg p-4">
      <div class="flex items-center mb-3">
        <div class={[
          "w-3 h-3 rounded-full mr-2",
          if(@adapter_color == "blue", do: "bg-blue-500", else: "bg-green-500")
        ]}></div>
        <h3 class={[
          "text-lg font-semibold",
          if(@adapter_color == "blue", do: "text-blue-300", else: "text-green-300")
        ]}>
          <%= @adapter_name %>
        </h3>
        <div class="ml-auto">
          <div class={[
            "w-2 h-2 rounded-full",
            if(@connected, do: "bg-green-500", else: "bg-neutral-500")
          ]}></div>
        </div>
      </div>

      <!-- Device Selection -->
      <div class="mb-3">
        <label class="block text-sm font-medium text-neutral-300 mb-2">Select Device</label>
        <form phx-change="connect_adapter" phx-value-adapter={@adapter_key} phx-target={@myself}>
          <select
            name="device"
            class={[
              "w-full px-3 py-2 bg-neutral-500 border border-neutral-400 rounded-md text-neutral-100 focus:outline-none focus:ring-2",
              if(@adapter_color == "blue", do: "focus:ring-blue-500", else: "focus:ring-green-500")
            ]}
          >
            <option value="">Select a device...</option>
            <%= for device <- @available_devices do %>
              <option value={device} selected={device == @device}>
                <%= device %>
              </option>
            <% end %>
          </select>
        </form>
      </div>


      <!-- Connection Settings -->
      <%= if @show_advanced do %>
        <form phx-change="set_adapter_settings" phx-value-adapter={@adapter_key} phx-debounce="100">
          <div class="grid grid-cols-2 gap-2 mb-3">
          <div>
            <label class="block text-xs font-medium text-neutral-300 mb-1">Baud Rate</label>
            <select
              name="baud_rate"
              value={Map.get(@settings, :baud_rate, 57600)}
              class={[
                "w-full px-2 py-1 bg-neutral-500 border border-neutral-400 rounded text-neutral-100 text-sm focus:outline-none focus:ring-1",
                if(@adapter_color == "blue", do: "focus:ring-blue-500", else: "focus:ring-green-500")
              ]}
            >
              <option value="9600" selected={Map.get(@settings, :baud_rate, 57600) == 9600}>9600</option>
              <option value="19200" selected={Map.get(@settings, :baud_rate, 57600) == 19200}>19200</option>
              <option value="38400" selected={Map.get(@settings, :baud_rate, 57600) == 38400}>38400</option>
              <option value="57600" selected={Map.get(@settings, :baud_rate, 57600) == 57600}>57600</option>
              <option value="115200" selected={Map.get(@settings, :baud_rate, 57600) == 115200}>115200</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-neutral-300 mb-1">Data Bits</label>
            <select
              name="data_bits"
              value={Map.get(@settings, :data_bits, 8)}
              class={[
                "w-full px-2 py-1 bg-neutral-500 border border-neutral-400 rounded text-neutral-100 text-sm focus:outline-none focus:ring-1",
                if(@adapter_color == "blue", do: "focus:ring-blue-500", else: "focus:ring-green-500")
              ]}
            >
              <option value="7" selected={Map.get(@settings, :data_bits, 8) == 7}>7</option>
              <option value="8" selected={Map.get(@settings, :data_bits, 8) == 8}>8</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-neutral-300 mb-1">Stop Bits</label>
            <select
              name="stop_bits"
              value={Map.get(@settings, :stop_bits, 1)}
              class={[
                "w-full px-2 py-1 bg-neutral-500 border border-neutral-400 rounded text-neutral-100 text-sm focus:outline-none focus:ring-1",
                if(@adapter_color == "blue", do: "focus:ring-blue-500", else: "focus:ring-green-500")
              ]}
            >
              <option value="1" selected={Map.get(@settings, :stop_bits, 1) == 1}>1</option>
              <option value="2" selected={Map.get(@settings, :stop_bits, 1) == 2}>2</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-neutral-300 mb-1">Parity</label>
            <select
              name="parity"
              value={Map.get(@settings, :parity, :none)}
              class={[
                "w-full px-2 py-1 bg-neutral-500 border border-neutral-400 rounded text-neutral-100 text-sm focus:outline-none focus:ring-1",
                if(@adapter_color == "blue", do: "focus:ring-blue-500", else: "focus:ring-green-500")
              ]}
            >
              <option value="none" selected={Map.get(@settings, :parity, :none) == :none}>None</option>
              <option value="even" selected={Map.get(@settings, :parity, :none) == :even}>Even</option>
              <option value="odd" selected={Map.get(@settings, :parity, :none) == :odd}>Odd</option>
            </select>
          </div>
        </div>

        <!-- Flow Control -->
        <div class="mb-3">
          <label class="flex items-center space-x-2">
            <input
              type="checkbox"
              name="flow_control"
              value="rts_cts"
              checked={Map.get(@settings, :flow_control, true)}
              class="w-4 h-4 text-blue-600 bg-neutral-500 border-neutral-400 rounded focus:ring-blue-500 focus:ring-2"
            />
            <span class="text-sm text-neutral-300">RTS/CTS Flow Control</span>
          </label>
          <p class="text-xs text-neutral-400 mt-1">Enable hardware handshaking (Request to Send/Clear to Send)</p>
        </div>
        </form>
      <% end %>

      <!-- Connection Status -->
      <%= if @connected do %>
        <div class="text-xs text-green-400 mb-2">
          ✓ Connected to: <%= @device %>
        </div>
        <div class="flex space-x-2">
          <button
            phx-click="disconnect_adapter"
            phx-value-adapter={@adapter_key}
            phx-target={@myself}
            class="px-3 py-1 bg-red-600 text-white text-sm rounded hover:bg-red-700"
          >
            Disconnect
          </button>
          <%= if @settings_changed do %>
            <button
              phx-click="reconnect_adapter"
              phx-value-adapter={@adapter_key}
              phx-value-device={@device}
              phx-target={@myself}
              class={[
                "px-3 py-1 text-white text-sm rounded transition-colors",
                if(@adapter_color == "blue", do: "bg-blue-600 hover:bg-blue-700", else: "bg-green-600 hover:bg-green-700")
              ]}
            >
              Reconnect
            </button>
          <% end %>
        </div>
      <% else %>
        <div class="text-xs text-neutral-400 mb-2">
          Not connected
        </div>
        <%= if @device do %>
          <button
            phx-click="connect_adapter"
            phx-value-adapter={@adapter_key}
            phx-value-device={@device}
            class={[
              "px-3 py-1 text-white text-sm rounded transition-colors",
              if(@adapter_color == "blue", do: "bg-blue-600 hover:bg-blue-700", else: "bg-green-600 hover:bg-green-700")
            ]}
          >
            Connect to <%= @device %>
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end
end
