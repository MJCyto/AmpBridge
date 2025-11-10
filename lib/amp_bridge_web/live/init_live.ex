defmodule AmpBridgeWeb.InitLive do
  use AmpBridgeWeb, :live_view
  require Logger

  alias AmpBridgeWeb.USBInitComponent
  alias AmpBridgeWeb.AmpConfigComponent
  alias AmpBridgeWeb.CommandLearningComponent
  alias AmpBridge.Devices
  alias AmpBridge.SerialManager

  @impl true
  def mount(_params, _session, socket) do
    amp_id = 1

    current_step =
      case Devices.get_device(amp_id) do
        nil ->
          :amp_config

        device ->
          cond do
            is_map(device.sources) && map_size(device.sources) > 0 &&
              is_map(device.zones) && map_size(device.zones) > 0 ->
              connection_status = SerialManager.get_connection_status()

              if connection_status.adapter_1.connected && connection_status.adapter_2.connected do
                if device.auto_detection_complete do
                  if device.command_learning_complete do
                    :finish
                  else
                    :command_learning
                  end
                else
                  :usb_assignment
                end
              else
                :usb_assignment
              end

            is_map(device.sources) && map_size(device.sources) > 0 ->
              :usb_assignment

            true ->
              :amp_config
          end
      end

    # Subscribe for command learning
    if connected?(socket) and current_step == :command_learning do
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "command_learned")
    end

    {:ok,
     assign(socket,
       page_title: "System Initialization",
       amp_id: amp_id,
       current_step: current_step,
       # Auto-detection state
       auto_detection_active: false,
       adapter_1_name: "Controller",
       adapter_2_name: "Amp",
       adapter_1_role: nil,
       adapter_2_role: nil,
       detection_status: "Ready to start auto-detection",
       # Command learning state
       last_command_learned: nil
     )}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, uri: uri)}
  end

  @impl true
  def handle_event("next_step", _params, socket) do
    case socket.assigns.current_step do
      :amp_config ->
        {:noreply, assign(socket, current_step: :usb_assignment)}

      :usb_assignment ->
        start_serial_relay_for_command_learning(socket)

      :command_learning ->
        mark_command_learning_complete(socket)

      :finish ->
        {:noreply, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("prev_step", _params, socket) do
    case socket.assigns.current_step do
      :usb_assignment ->
        {:noreply, assign(socket, current_step: :amp_config)}

      :command_learning ->
        {:noreply, assign(socket, current_step: :usb_assignment)}

      :finish ->
        {:noreply, assign(socket, current_step: :command_learning)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:amp_config_saved, config}, socket) do
    Logger.info("Amplifier configuration saved: #{inspect(config)}")
    {:noreply, assign(socket, current_step: :usb_assignment)}
  end

  @impl true
  def handle_info({:sources_updated, _sources}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:zones_updated, _zones}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:start_auto_detection, _amp_id}, socket) do
    Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")

    {:noreply,
     assign(socket,
       auto_detection_active: true,
       detection_status: "Listening for communication... Send a command from your controller now!"
     )}
  end

  @impl true
  def handle_info({:stop_auto_detection, _amp_id}, socket) do
    Phoenix.PubSub.unsubscribe(AmpBridge.PubSub, "serial_data")

    {:noreply,
     assign(socket,
       auto_detection_active: false,
       detection_status: "Auto-detection stopped"
     )}
  end

  @impl true
  def handle_info({:update_adapter_name, adapter, name}, socket) do
    case adapter do
      "adapter_1" ->
        socket = assign(socket, adapter_1_name: name)
        save_adapter_name_immediately(socket, "adapter_1", name)
        {:noreply, socket}

      "adapter_2" ->
        socket = assign(socket, adapter_2_name: name)
        save_adapter_name_immediately(socket, "adapter_2", name)
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end


  @impl true
  def handle_info({:serial_data, data, _decoded, adapter_info}, socket) do
    if socket.assigns.auto_detection_active do
      adapter = adapter_info.adapter

      if socket.assigns.adapter_1_role == nil && socket.assigns.adapter_2_role == nil do
        {adapter_1_role, adapter_2_role} =
          case adapter do
            :adapter_1 -> {"controller", "amp"}
            :adapter_2 -> {"amp", "controller"}
          end

        {adapter_1_name, adapter_2_name} =
          case adapter do
            :adapter_1 -> {"Controller", "Amp"}
            :adapter_2 -> {"Amp", "Controller"}
          end

        Logger.info("Auto-detection: adapter=#{adapter}, adapter_1_role=#{adapter_1_role}, adapter_2_role=#{adapter_2_role}, adapter_1_name=#{adapter_1_name}, adapter_2_name=#{adapter_2_name}")

        socket =
          assign(socket,
            adapter_1_role: adapter_1_role,
            adapter_2_role: adapter_2_role,
            adapter_1_name: adapter_1_name,
            adapter_2_name: adapter_2_name,
            detection_status:
              "Roles detected! Adapter 1: #{adapter_1_role}, Adapter 2: #{adapter_2_role}"
          )

        save_adapter_roles_immediately(socket)
      else
        {:noreply, socket}
      end
    else
      if socket.assigns.current_step == :command_learning do
        Logger.info(
          "Command learning: Received data from #{adapter_info.adapter} - #{AmpBridge.SerialManager.format_hex(data)}"
        )
      end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:download_file, %{content: content, filename: filename, content_type: content_type}}, socket) do
    {:noreply,
     socket
     |> push_event("download_file", %{content: content, filename: filename, content_type: content_type})}
  end

  @impl true
  def handle_info({:command_learned, device_id, control_type, zone}, socket) do
    Logger.info("Command learned: #{control_type} for zone #{zone}")

    if socket.assigns.current_step == :command_learning and socket.assigns.amp_id == device_id do
      {:noreply,
       socket
       |> assign(:last_command_learned, System.monotonic_time(:millisecond))
       |> put_flash(:info, "Command learned: #{control_type} for zone #{zone}")}
    else
      {:noreply, socket}
    end
  end

  defp mark_command_learning_complete(socket) do
    case Devices.get_device(socket.assigns.amp_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        case Devices.update_device(device, %{command_learning_complete: true}) do
          {:ok, _updated_device} ->
            Logger.info("Command learning marked as complete for device #{socket.assigns.amp_id}")

            {:noreply,
             socket
             |> assign(current_step: :finish)
             |> put_flash(
               :info,
               "Command learning completed! You can always learn more commands later."
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to mark command learning as complete")}
        end
    end
  end

  defp start_serial_relay_for_command_learning(socket) do
    connection_status = SerialManager.get_connection_status()

    if connection_status.adapter_1.connected && connection_status.adapter_2.connected do
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "command_learned")

      case AmpBridge.SerialRelay.start_relay() do
        :ok ->
          Logger.info("Serial relay started for command learning")
          relay_status = AmpBridge.SerialRelay.relay_status()
          Logger.info("Relay status: #{inspect(relay_status)}")

          {:noreply,
           socket
           |> assign(current_step: :command_learning)
           |> put_flash(:info, "Serial relay started - ready for command learning")}

        {:error, :already_active} ->
          Logger.info("Serial relay already active for command learning")
          relay_status = AmpBridge.SerialRelay.relay_status()
          Logger.info("Relay status: #{inspect(relay_status)}")

          {:noreply,
           socket
           |> assign(current_step: :command_learning)
           |> put_flash(:info, "Ready for command learning")}

        {:error, reason} ->
          Logger.error("Failed to start serial relay: #{reason}")

          {:noreply,
           socket
           |> assign(current_step: :command_learning)
           |> put_flash(:error, "Failed to start serial relay: #{reason}")}
      end
    else
      {:noreply,
       socket
       |> assign(current_step: :command_learning)
       |> put_flash(:error, "Both adapters must be connected for command learning")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen p-8">
      <div class="max-w-4xl mx-auto">
        <!-- Header -->
        <div class="mb-8">
          <div class="flex justify-between items-start">
              <h1 class="text-3xl font-bold text-neutral-100 mb-2">System Initialization</h1>
            <a href={~p"/"} class="inline-flex items-center px-4 py-2 border border-neutral-600 text-sm font-medium rounded-md text-neutral-300 bg-neutral-700 hover:bg-neutral-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
              </svg>
              Back to Home
            </a>
          </div>
        </div>

        <!-- Progress Steps -->
        <div class="mb-8">
          <div class="flex justify-between text-sm">
            <span class={if @current_step == :amp_config, do: "text-teal-400 font-medium", else: "text-neutral-400"}>Sources & Zones</span>
            <span class={if @current_step == :usb_assignment, do: "text-teal-400 font-medium", else: "text-neutral-400"}>Serial</span>
            <span class={if @current_step == :command_learning, do: "text-teal-400 font-medium", else: "text-neutral-400"}>Command Learning</span>
            <span class={if @current_step == :finish, do: "text-teal-400 font-medium", else: "text-neutral-400"}>Finish</span>
          </div>
        </div>

                <!-- Step Content -->
        <div class="bg-neutral-700 rounded-lg shadow-lg border border-neutral-600">
          <%= if @current_step == :amp_config do %>
            <div class="p-6">
              <div class="mb-6">
                <h2 class="text-xl font-semibold text-neutral-100 mb-2">Step 1: Sources & Zones</h2>
                <p class="text-neutral-400">Let's start by configuring your amplifier's basic settings and capabilities.</p>
              </div>

              <.live_component
                module={AmpConfigComponent}
                id="amp-config"
                amp_id={@amp_id}
              />

              <div class="flex justify-between">
                <div></div>
                <button phx-click="next_step" class="bg-teal-600 hover:bg-teal-700 text-white px-6 py-2 rounded-md font-medium">
                  Next: Serial
                </button>
              </div>
            </div>
          <% end %>

          <%= if @current_step == :usb_assignment do %>
            <div class="p-6">
              <div class="mb-6">
                <h2 class="text-xl font-semibold text-neutral-100 mb-2">Step 2: USB Serial Adapters</h2>
                <p class="text-neutral-400">Connect and configure USB-to-serial adapters for your amplifier.</p>
              </div>

              <.live_component
                module={USBInitComponent}
                id="usb-init"
                amp_id={@amp_id}
                auto_detection_active={@auto_detection_active}
                adapter_1_name={@adapter_1_name}
                adapter_2_name={@adapter_2_name}
                adapter_1_role={@adapter_1_role}
                adapter_2_role={@adapter_2_role}
                detection_status={@detection_status}
              />

              <div class="flex justify-between mt-3">
                <button phx-click="prev_step" class="bg-neutral-600 hover:bg-neutral-500 text-white px-6 py-2 rounded-md font-medium">
                  Back: Sources & Zones
                </button>
                <button phx-click="next_step" class="bg-teal-600 hover:bg-teal-700 text-white px-6 py-2 rounded-md font-medium">
                  Next: Command Learning
                </button>
              </div>
            </div>
          <% end %>

          <%= if @current_step == :command_learning do %>
            <div class="p-6">
              <div class="mb-6">
                <h2 class="text-xl font-semibold text-neutral-100 mb-2">Step 3: Command Learning (Optional)</h2>
                <p class="text-neutral-400">Learn the commands for your amplifier system. You can skip this step and learn commands later if needed.</p>
              </div>

              <.live_component
                module={CommandLearningComponent}
                id="command-learning"
                amp_id={@amp_id}
                last_command_learned={@last_command_learned}
              />

              <div class="flex justify-between">
                <button phx-click="prev_step" class="bg-neutral-600 hover:bg-neutral-500 text-white px-6 py-2 rounded-md font-medium">
                  Back: Serial
                </button>
                <button phx-click="next_step" class="bg-teal-600 hover:bg-teal-700 text-white px-6 py-2 rounded-md font-medium">
                  Complete Setup
                </button>
              </div>
            </div>
          <% end %>

          <%= if @current_step == :zone_setup do %>
            <div class="p-6">
              <div class="mb-6">
                <h2 class="text-xl font-semibold text-neutral-100 mb-2">Step 4: Zone Setup</h2>
                <p class="text-neutral-400">Set up audio zones and speaker groups for your system.</p>
              </div>

              <div class="text-center py-8 text-neutral-400">
                <p>Zone setup coming soon...</p>
              </div>

              <div class="flex justify-between">
                <button phx-click="prev_step" class="bg-neutral-600 hover:bg-neutral-500 text-white px-6 py-2 rounded-md font-medium">
                  Back: USB Assignment
                </button>
                <button phx-click="next_step" class="bg-teal-600 hover:bg-teal-700 text-white px-6 py-2 rounded-md font-medium">
                  Next: Finish
                </button>
              </div>
            </div>
          <% end %>

          <%= if @current_step == :finish do %>
            <div class="p-6">
              <div class="mb-6">
                <h2 class="text-xl font-semibold text-neutral-100 mb-2">Step 5: Setup Complete!</h2>
              </div>

              <div class="text-center py-8">
                <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-teal-900 mb-4">
                  <svg class="h-6 w-6 text-teal-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
                  </svg>
                </div>
                <h3 class="text-lg font-medium text-neutral-100 mb-2">All Done!</h3>
                <p class="text-neutral-400">Your system is ready to go. Click Done to start using AmpBridge.</p>
              </div>

              <div class="flex justify-between">
                <button phx-click="prev_step" class="bg-neutral-600 hover:bg-neutral-500 text-white px-6 py-2 rounded-md font-medium">
                  Back: Command Learning
                </button>
                <button phx-click="next_step" class="bg-teal-600 hover:bg-teal-700 text-white px-6 py-2 rounded-md font-medium">
                  Done
                </button>
                </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp save_adapter_roles_immediately(socket) do
    case Devices.get_device(1) do
      nil ->
        Logger.warning("Device not found when trying to save adapter roles")
        {:noreply, socket}

      device ->
        attrs = %{
          auto_detection_complete: true,
          adapter_1_name: socket.assigns.adapter_1_name || "Controller",
          adapter_2_name: socket.assigns.adapter_2_name || "Amp",
          adapter_1_role: socket.assigns.adapter_1_role,
          adapter_2_role: socket.assigns.adapter_2_role
        }

        case Devices.update_device(device, attrs) do
          {:ok, _updated_device} ->
            Logger.info("Adapter roles saved automatically after auto-detection")
            {:noreply, put_flash(socket, :info, "Auto-detection complete! Adapter roles saved automatically.")}

          {:error, changeset} ->
            Logger.error("Failed to save adapter roles automatically: #{inspect(changeset)}")
            {:noreply, put_flash(socket, :error, "Failed to save adapter roles automatically")}
        end
    end
  end

  defp save_adapter_name_immediately(_socket, adapter, name) do
    case Devices.get_device(1) do
      nil ->
        Logger.warning("Device not found when trying to save adapter name")
        :ok

      device ->
        attrs = case adapter do
          "adapter_1" -> %{adapter_1_name: name}
          "adapter_2" -> %{adapter_2_name: name}
          _ -> %{}
        end

        case Devices.update_device(device, attrs) do
          {:ok, _updated_device} ->
            Logger.info("Adapter #{adapter} name saved: #{name}")
            :ok

          {:error, changeset} ->
            Logger.error("Failed to save adapter #{adapter} name: #{inspect(changeset)}")
            :ok
        end
    end
  end
end
