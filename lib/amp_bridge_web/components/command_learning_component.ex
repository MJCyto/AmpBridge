defmodule AmpBridgeWeb.CommandLearningComponent do
  @moduledoc """
  LiveComponent for learning amplifier commands during initialization.
  """
  use AmpBridgeWeb, :live_component
  require Logger

  @impl true
  def mount(socket) do
    # Subscribe to command learned messages
    Phoenix.PubSub.subscribe(AmpBridge.PubSub, "command_learned")
    {:ok, assign(socket, learning_status: %{}, learned_commands: [], show_help_modal: false)}
  end

  @impl true
  def update(assigns, socket) do
    # Load device configuration to show configured zones and sources
    device = AmpBridge.Devices.get_device(assigns.amp_id)

    # Check if we need to refresh learned commands (when last_command_learned changes)
    should_refresh = Map.has_key?(assigns, :last_command_learned) &&
                     assigns.last_command_learned != Map.get(socket.assigns, :last_command_learned)

    socket =
      if device && device.zones && map_size(device.zones) > 0 do
        # Extract configured zones and sources
        zones_map = device.zones
        sources_map = device.sources || %{}

        zone_numbers =
          zones_map
          |> Map.keys()
          |> Enum.map(&String.to_integer/1)
          # Zones in database are already 0-based, no conversion needed
          |> Enum.sort()

        sources_list =
          sources_map
          |> Map.keys()
          |> Enum.sort()
          |> Enum.map(fn key ->
            source_data = Map.get(sources_map, key)
            source_name = Map.get(source_data, "name", "Source #{String.to_integer(key) + 1}")
            {String.to_integer(key), source_name}
          end)

        # Load learned commands from database (refresh if needed)
        learned_commands = if should_refresh do
          Logger.info("Refreshing learned commands due to new command learned")
          load_learned_commands(assigns.amp_id)
        else
          # Always load learned commands on initial render or if not cached
          case Map.get(socket.assigns, :learned_commands) do
            nil ->
              Logger.info("Loading learned commands for first time")
              load_learned_commands(assigns.amp_id)
            commands when is_list(commands) and length(commands) > 0 ->
              Logger.info("Using cached learned commands (#{length(commands)} commands)")
              commands
            _ ->
              Logger.info("Cached learned commands empty, loading from database")
              load_learned_commands(assigns.amp_id)
          end
        end

        assign(
          socket,
          assigns
          |> Map.put(:device_config, device)
          |> Map.put(:configured_zones, zone_numbers)
          |> Map.put(:configured_sources, sources_list)
          |> Map.put(:learned_commands, learned_commands)
          |> Map.put(:learning_state, %{})  # Track which buttons are learning
        )
      else
        # Fallback to default zones 0-7 if no configuration (0-based)
        Logger.info("CommandLearningComponent: No device zones configured, using default zones 0-7")
        default_zones = [0, 1, 2, 3, 4, 5, 6, 7]

        # Load learned commands from database (refresh if needed)
        learned_commands = if should_refresh do
          Logger.info("Refreshing learned commands due to new command learned")
          load_learned_commands(assigns.amp_id)
        else
          # Always load learned commands on initial render or if not cached
          case Map.get(socket.assigns, :learned_commands) do
            nil ->
              Logger.info("Loading learned commands for first time (fallback)")
              load_learned_commands(assigns.amp_id)
            commands when is_list(commands) and length(commands) > 0 ->
              Logger.info("Using cached learned commands (#{length(commands)} commands) (fallback)")
              commands
            _ ->
              Logger.info("Cached learned commands empty, loading from database (fallback)")
              load_learned_commands(assigns.amp_id)
          end
        end

        assign(
          socket,
          assigns
          |> Map.put(:device_config, device)
          |> Map.put(:configured_zones, default_zones)
          |> Map.put(:configured_sources, [])
          |> Map.put(:learned_commands, learned_commands)
          |> Map.put(:learning_state, %{})  # Track which buttons are learning
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("export_commands", _params, socket) do
    device_id = socket.assigns.amp_id

    # Generate export data
    export_data = AmpBridge.LearnedCommands.export_device_commands(device_id)

    # Check if there are any commands to export
    total_commands = Map.get(export_data, "metadata") |> Map.get("total_commands", 0)

    if total_commands == 0 do
      {:noreply, put_flash(socket, :warning, "No commands found to export. Learn some commands first!")}
    else
      # Convert to JSON
      case Jason.encode(export_data, pretty: true) do
        {:ok, json_string} ->
          # Generate filename with timestamp
          timestamp = DateTime.utc_now() |> DateTime.to_date() |> Date.to_string()
          filename = "ampbridge_commands_#{timestamp}.json"

          # Send file download event to parent LiveView and push event directly
          parent_pid = socket.root_pid
          if parent_pid do
            send(parent_pid, {:download_file, %{content: json_string, filename: filename, content_type: "application/json"}})
          end

          {:noreply,
           socket
           |> put_flash(:info, "Commands exported successfully! (#{total_commands} commands)")
           |> push_event("download_file", %{content: json_string, filename: filename, content_type: "application/json"})}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to export commands. Please try again.")}
      end
    end
  end

  @impl true
  def handle_event("import_commands", %{"content" => content}, socket) do
    device_id = socket.assigns.amp_id

    # Import commands
    case AmpBridge.LearnedCommands.import_device_commands(device_id, content) do
      {:ok, result} ->
        message = "Successfully imported #{result.successful_imports} commands"
        message = if result.failed_imports > 0 do
          message <> " (#{result.failed_imports} failed)"
        else
          message
        end

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(last_command_learned: %{timestamp: DateTime.utc_now()})}  # Trigger refresh

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Import failed: #{reason}")}
    end
  end

  @impl true
  def handle_event("import_commands", %{"error" => error}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to read file: #{error}")}
  end

  @impl true
  def handle_event("learn_mute", %{"zone" => zone_str}, socket) do
    Logger.info("CommandLearningComponent: Received learn_mute event for zone #{zone_str}")
    zone_num = String.to_integer(zone_str)

    # Set learning state for this button
    learning_key = "mute_#{zone_num}"
    updated_learning_state = Map.put(socket.assigns.learning_state, learning_key, true)

    socket = assign(socket, :learning_state, updated_learning_state)
    start_learning(socket, "mute", zone_num)
  end

  @impl true
  def handle_event("learn_unmute", %{"zone" => zone_str}, socket) do
    Logger.info("CommandLearningComponent: Received learn_unmute event for zone #{zone_str}")
    zone_num = String.to_integer(zone_str)

    # Set learning state for this button
    learning_key = "unmute_#{zone_num}"
    updated_learning_state = Map.put(socket.assigns.learning_state, learning_key, true)

    socket = assign(socket, :learning_state, updated_learning_state)
    start_learning(socket, "unmute", zone_num)
  end

  @impl true
  def handle_event(
        "learn_change_source",
        %{"zone" => zone_str, "source_index" => source_index_str},
        socket
      ) do
    Logger.info(
      "CommandLearningComponent: Received learn_change_source event for zone #{zone_str}, source #{source_index_str}"
    )

    zone_num = String.to_integer(zone_str)
    source_index = String.to_integer(source_index_str)

    # Set learning state for this button
    learning_key = "change_source_#{zone_num}_#{source_index}"
    updated_learning_state = Map.put(socket.assigns.learning_state, learning_key, true)

    socket = assign(socket, :learning_state, updated_learning_state)
    start_learning(socket, "change_source", zone_num, source_index: source_index)
  end

  @impl true
  def handle_event("learn_turn_off", %{"zone" => zone_str}, socket) do
    Logger.info("CommandLearningComponent: Received learn_turn_off event for zone #{zone_str}")
    zone_num = String.to_integer(zone_str)

    # Set learning state for this button
    learning_key = "turn_off_#{zone_num}"
    updated_learning_state = Map.put(socket.assigns.learning_state, learning_key, true)

    socket = assign(socket, :learning_state, updated_learning_state)
    start_learning(socket, "turn_off", zone_num)
  end

  @impl true
  def handle_event("show_help_modal", _params, socket) do
    {:noreply, assign(socket, show_help_modal: true)}
  end

  @impl true
  def handle_event("hide_help_modal", _params, socket) do
    {:noreply, assign(socket, show_help_modal: false)}
  end

  def handle_info({:command_learned, _device_id, control_type, zone}, socket) do
    Logger.info("CommandLearningComponent: Command learned - #{control_type} for zone #{zone}")

    # Clear learning state for this command
    learning_key = case control_type do
      "mute" -> "mute_#{zone}"
      "unmute" -> "unmute_#{zone}"
      "turn_off" -> "turn_off_#{zone}"
      _ -> nil  # For other types, we'd need more info to construct the key
    end

    updated_learning_state = if learning_key do
      Map.delete(socket.assigns.learning_state, learning_key)
    else
      socket.assigns.learning_state
    end

    {:noreply, assign(socket, :learning_state, updated_learning_state)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-neutral-800 rounded-lg p-6">
        <div class="flex justify-between items-start mb-4">
          <h4 class="text-md font-semibold text-neutral-100">Instructions</h4>
          <button
            phx-click="show_help_modal"
            phx-target={@myself}
            class="text-sm text-teal-400 hover:text-teal-300 underline"
          >
            Why are mute/unmute showing as already learned?
          </button>
        </div>
        <ol class="text-sm text-neutral-400 space-y-2 list-decimal list-inside">
          <li>Click a button below to learn commands for your amplifier system.</li>
          <li>Go to the manufacturer's app (NICE / G! Viewer)</li>
          <li>Tap the corresponding control in the manufacturer's app</li>
          <li>The data sent by your controller will be used in the future to control the amplifier</li>
        </ol>
      </div>
      <!-- Command Learning Buttons -->
      <%= if @device_config && length(@configured_zones) > 0 do %>
        <div class="bg-neutral-700 rounded-lg py-4">
          <div class="px-6">
            <!-- Top Row -->
            <div class="flex justify-between items-center mb-2">
              <h4 class="text-lg font-semibold text-neutral-200">Command Learning</h4>
              <!-- Import/Export Controls -->
              <div class="flex items-center gap-2">
                <!-- Export Button -->
                <button
                  phx-click="export_commands"
                  phx-target={@myself}
                  class="bg-green-600 hover:bg-green-700 text-white px-3 py-1 rounded text-sm font-medium transition-colors flex items-center gap-1"
                  title="Export all learned commands to JSON file"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                  </svg>
                  Export
                </button>

                <!-- Import Button -->
                <label class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded text-sm font-medium transition-colors flex items-center gap-1 cursor-pointer">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
                  </svg>
                  Import
                  <input
                    type="file"
                    id="file-upload-input"
                    accept=".json"
                    phx-hook="FileUploadHook"
                    phx-target={@myself}
                    phx-value-event="import_commands"
                    class="hidden"
                  />
                </label>

                <!-- Info Tooltip -->
                <div class="relative group">
                  <button
                    type="button"
                    class="text-neutral-400 hover:text-neutral-300 transition-colors"
                    aria-label="Share Your Setup information"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </button>
                  <!-- Tooltip -->
                  <div class="absolute right-0 top-full mt-2 w-80 bg-neutral-800 rounded-lg p-3 text-sm text-neutral-300 shadow-xl opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200 z-50">
                    <div class="flex items-start gap-2">
                      <svg class="w-4 h-4 mt-0.5 text-blue-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      <div>
                        <p class="font-medium text-neutral-200 mb-1">• Share Your Setup</p>
                        <p class="text-neutral-400">
                          Export your learned commands to share with the community, or import commands from others with the same amplifier model.
                          The JSON file includes all zones and their learned commands for easy setup sharing.
                        </p>
                      </div>
                    </div>
                    <!-- Tooltip arrow -->
                    <div class="absolute bottom-full right-4 w-0 h-0 border-l-8 border-r-8 border-b-8 border-l-transparent border-r-transparent border-b-neutral-800"></div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Zone count text below heading -->
            <div class="text-sm text-neutral-400 mb-4">
              Learning commands for <%= length(@configured_zones) %> configured zones
            </div>
          </div>

          <div class="overflow-x-auto px-6 pb-2 command-learning-zones">
            <div class="flex gap-6">
            <%= for zone <- @configured_zones do %>
              <div class="flex-shrink-0 w-48">
                <div class="bg-neutral-800 rounded-lg p-4">
                  <h5 class="text-md font-semibold text-neutral-100 mb-4 text-center">
                    <%= get_zone_name(@device_config, zone) || "Zone #{zone + 1}" %>
                  </h5>

                  <!-- Mute/Unmute Buttons -->
                  <div class="space-y-2 mb-4">
                    <button
                      phx-click="learn_mute"
                      phx-value-zone={zone}
                      phx-target={@myself}
                      disabled={Map.get(@learning_state, "mute_#{zone}", false)}
                      class={[
                        "w-full text-white px-3 py-2 rounded text-sm font-medium transition-colors flex items-center justify-center gap-2",
                        if Map.get(@learning_state, "mute_#{zone}", false) do
                          "bg-red-500 cursor-not-allowed"
                        else
                          "bg-red-600 hover:bg-red-700"
                        end
                      ]}
                    >
                      <%= cond do %>
                        <% Map.get(@learning_state, "mute_#{zone}", false) -> %>
                          <!-- Spinner -->
                          <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                          Learning...
                        <% is_command_learned?(@learned_commands, "mute", zone) -> %>
                          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                          </svg>
                          Mute
                        <% true -> %>
                          Mute
                      <% end %>
                    </button>
                    <button
                      phx-click="learn_unmute"
                      phx-value-zone={zone}
                      phx-target={@myself}
                      disabled={Map.get(@learning_state, "unmute_#{zone}", false)}
                      class={[
                        "w-full text-white px-3 py-2 rounded text-sm font-medium transition-colors flex items-center justify-center gap-2",
                        if Map.get(@learning_state, "unmute_#{zone}", false) do
                          "bg-green-500 cursor-not-allowed"
                        else
                          "bg-green-600 hover:bg-green-700"
                        end
                      ]}
                    >
                      <%= cond do %>
                        <% Map.get(@learning_state, "unmute_#{zone}", false) -> %>
                          <!-- Spinner -->
                          <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                          Learning...
                        <% is_command_learned?(@learned_commands, "unmute", zone) -> %>
                          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                          </svg>
                          Unmute
                        <% true -> %>
                          Unmute
                      <% end %>
                    </button>
                  </div>

                  <!-- Source Buttons -->
                  <div class="space-y-2 mb-4">
                    <div class="text-xs text-neutral-400 mb-2">Sources:</div>
                    <%= for {source_index, source_name} <- get_zone_sources_with_index(@device_config, zone) do %>
                      <button
                        phx-click="learn_change_source"
                        phx-value-zone={zone}
                        phx-value-source_index={source_index}
                        phx-target={@myself}
                        disabled={Map.get(@learning_state, "change_source_#{zone}_#{source_index}", false)}
                        class={[
                          "w-full text-white px-3 py-2 rounded text-sm font-medium transition-colors flex items-center justify-center gap-2",
                          if Map.get(@learning_state, "change_source_#{zone}_#{source_index}", false) do
                            "bg-teal-500 cursor-not-allowed"
                          else
                            "bg-teal-600 hover:bg-teal-700"
                          end
                        ]}
                      >
                        <%= cond do %>
                          <% Map.get(@learning_state, "change_source_#{zone}_#{source_index}", false) -> %>
                            <!-- Spinner -->
                            <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                            </svg>
                            Learning...
                          <% is_command_learned?(@learned_commands, "change_source", zone, source_index: source_index) -> %>
                            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                            </svg>
                            <%= source_name %>
                          <% true -> %>
                            <%= source_name %>
                        <% end %>
                      </button>
                    <% end %>
                  </div>

                  <!-- Turn Off Button -->
                  <div class="space-y-2">
                    <button
                      phx-click="learn_turn_off"
                      phx-value-zone={zone}
                      phx-target={@myself}
                      disabled={Map.get(@learning_state, "turn_off_#{zone}", false)}
                      class={[
                        "w-full text-white px-3 py-2 rounded text-sm font-medium transition-colors flex items-center justify-center gap-2",
                        if Map.get(@learning_state, "turn_off_#{zone}", false) do
                          "bg-neutral-500 cursor-not-allowed"
                        else
                          "bg-neutral-600 hover:bg-neutral-700"
                        end
                      ]}
                    >
                      <%= cond do %>
                        <% Map.get(@learning_state, "turn_off_#{zone}", false) -> %>
                          <!-- Spinner -->
                          <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                          Learning...
                        <% is_command_learned?(@learned_commands, "turn_off", zone) -> %>
                          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                          </svg>
                          Turn Off
                        <% true -> %>
                          Turn Off
                      <% end %>
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
            </div>
          </div>
        </div>
      <% else %>
        <div class="bg-yellow-900/20 border border-yellow-600 rounded-lg p-6">
          <div class="text-center text-yellow-400">
            <p class="font-medium">No Configuration Found</p>
            <p class="text-sm mt-2">Please complete the amplifier configuration first.</p>
          </div>
        </div>
      <% end %>

      <!-- Help Modal -->
      <%= if @show_help_modal do %>
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
          <div class="flex items-center justify-center min-h-screen p-4">
            <!-- Background overlay -->
            <div
              class="fixed inset-0 bg-neutral-900 bg-opacity-75 transition-opacity"
              aria-hidden="true"
              phx-click="hide_help_modal"
              phx-target={@myself}
            ></div>

            <!-- Modal panel -->
            <div
              class="relative bg-neutral-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all max-w-lg w-full"
              phx-click=""
            >
              <div class="bg-neutral-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <div class="sm:flex sm:items-start">
                  <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-teal-900 sm:mx-0 sm:h-10 sm:w-10">
                    <svg class="h-6 w-6 text-teal-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </div>
                  <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
                    <h3 class="text-lg leading-6 font-medium text-neutral-100" id="modal-title">
                      Pre-learned Commands
                    </h3>
                    <div class="mt-2">
                      <p class="text-sm text-neutral-400">
                        The mute and unmute commands are showing as already learned because AmpBridge ships with these commands ready to use. I'm somewhat confident they would work across different setups, but other commands I'm not so sure about.
                      </p>
                      <p class="text-sm text-neutral-400 mt-3">
                        If these pre-learned commands don't work for your setup, you can still use the UI to learn the commands and overwrite the ones that the app comes with. You can also come back to this command learning interface at any time from the main page.
                      </p>
                    </div>
                  </div>
                </div>
              </div>
              <div class="bg-neutral-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                <button
                  phx-click="hide_help_modal"
                  phx-target={@myself}
                  type="button"
                  class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-teal-600 text-base font-medium text-white hover:bg-teal-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 sm:ml-3 sm:w-auto sm:text-sm"
                >
                  Got it
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

    </div>
    """
  end

  defp start_learning(socket, control_type, zone, opts \\ []) do
    device_id = socket.assigns.amp_id

    case AmpBridge.CommandLearner.start_command_learning(device_id, control_type, zone, opts) do
      {:ok, :learning_started, _pid} ->
        # Update learning status
        learning_status =
          Map.put(socket.assigns.learning_status, "#{control_type}_#{zone}", :learning)

        # Refresh learned commands
        learned_commands = load_learned_commands(device_id)

        {:noreply,
         socket
         |> assign(:learning_status, learning_status)
         |> assign(:learned_commands, learned_commands)
         |> put_flash(
           :info,
           "Learning mode started for #{control_type} zone #{zone}. Now go to your manufacturer's app and click the same control."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start learning: #{reason}")}
    end
  end


  # Helper function to get zone name from device config
  defp get_zone_name(device_config, zone) do
    if device_config && device_config.zones do
      # Zones in database are already 0-based, no conversion needed
      zone_key = to_string(zone)

      case Map.get(device_config.zones, zone_key) do
        %{"name" => name} when is_binary(name) and name != "" -> name
        _ -> nil
      end
    else
      nil
    end
  end

  # Helper function to get sources with their indices for a specific zone
  defp get_zone_sources_with_index(device_config, _zone) do
    if device_config && device_config.sources do
      # Get all configured sources as a list of {index, name} tuples
      device_config.sources
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn key ->
        source_index = String.to_integer(key)
        source_data = Map.get(device_config.sources, key)
        source_name = Map.get(source_data, "name", "Source #{source_index + 1}")
        {source_index, source_name}
      end)
    else
      []
    end
  end

  defp load_learned_commands(device_id) do
    # Load mute/unmute commands from serial_commands table (used by homepage)
    serial_commands = load_commands_from_serial_commands()

    # Load other commands from learned_commands table (change_source, volume, etc.)
    other_commands = load_commands_from_learned_commands(device_id)

    # Combine both lists and sort by learned_at (most recent first)
    all_commands = (serial_commands ++ other_commands)
    |> Enum.sort_by(& &1.learned_at, {:desc, NaiveDateTime})

    Logger.info("Loaded #{length(serial_commands)} serial commands + #{length(other_commands)} learned commands = #{length(all_commands)} total for device #{device_id}")

    all_commands
  end

  defp load_commands_from_serial_commands do
    alias AmpBridge.Repo
    alias AmpBridge.SerialCommand

    # Get all serial commands from the database
    serial_commands = Repo.all(SerialCommand)

    learned_commands = []

    # Process each zone's commands
    for serial_command <- serial_commands do
      zone = serial_command.zone_index
      zone_commands = []

      # Process mute command if it exists
      mute_commands = if serial_command.mute != "[]" do
        case Jason.decode(serial_command.mute) do
          {:ok, mute_array} ->
            hex_values = Enum.map(mute_array, fn base64_binary ->
              case Base.decode64(base64_binary) do
                {:ok, binary} -> :binary.bin_to_list(binary) |> hd()
                {:error, _} -> 0
              end
            end)
            format_hex_sequence_from_values(hex_values)
          {:error, _} -> "Invalid mute data"
        end
      else
        nil
      end

      # Process unmute command if it exists
      unmute_commands = if serial_command.unmute != "[]" do
        case Jason.decode(serial_command.unmute) do
          {:ok, unmute_array} ->
            hex_values = Enum.map(unmute_array, fn base64_binary ->
              case Base.decode64(base64_binary) do
                {:ok, binary} -> :binary.bin_to_list(binary) |> hd()
                {:error, _} -> 0
              end
            end)
            format_hex_sequence_from_values(hex_values)
          {:error, _} -> "Invalid unmute data"
        end
      else
        nil
      end

      # Add mute command if it exists
      zone_commands = if mute_commands do
        [%{
          control_type: "mute",
          zone: zone,
          source_index: nil,
          volume_level: nil,
          controller_sequence: mute_commands,
          amp_sequence: "Not available",
          learned_at: serial_command.updated_at,
          zone_name: "Zone #{zone + 1}",
          source_name: nil
        } | zone_commands]
      else
        zone_commands
      end

      # Add unmute command if it exists
      zone_commands = if unmute_commands do
        [%{
          control_type: "unmute",
          zone: zone,
          source_index: nil,
          volume_level: nil,
          controller_sequence: unmute_commands,
          amp_sequence: "Not available",
          learned_at: serial_command.updated_at,
          zone_name: "Zone #{zone + 1}",
          source_name: nil
        } | zone_commands]
      else
        zone_commands
      end

      learned_commands ++ zone_commands
    end
    |> List.flatten()
  end

  defp load_commands_from_learned_commands(device_id) do
    alias AmpBridge.LearnedCommands

    # Get device configuration for names
    device_config = AmpBridge.Devices.get_device(device_id)

    commands = LearnedCommands.list_commands_for_device(device_id)

    commands
    |> Enum.map(fn command ->
      %{
        control_type: command.control_type,
        zone: command.zone,
        source_index: command.source_index,
        volume_level: command.volume_level,
        controller_sequence: format_hex_sequence_from_binary(command.command_sequence),
        amp_sequence: format_hex_sequence_from_binary(command.response_pattern),
        learned_at: command.learned_at,
        zone_name: get_zone_name(device_config, command.zone),
        source_name: get_source_name(device_config, command.source_index)
      }
    end)
  end

  defp format_hex_sequence_from_binary(nil), do: "Not learned"
  defp format_hex_sequence_from_binary(<<>>), do: "Not learned"
  defp format_hex_sequence_from_binary(sequence) do
    sequence
    |> :binary.bin_to_list()
    |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
    |> Enum.join(" ")
    |> String.upcase()
  end

  defp get_source_name(device_config, source_index) do
    if device_config && device_config.sources && source_index != nil do
      source_key = to_string(source_index)

      case Map.get(device_config.sources, source_key) do
        %{"name" => name} when is_binary(name) and name != "" -> name
        _ -> "Source #{source_index + 1}"
      end
    else
      if source_index != nil do
        "Source #{source_index + 1}"
      else
        nil
      end
    end
  end

  # Helper function to check if a specific command is learned
  defp is_command_learned?(learned_commands, control_type, zone, opts \\ []) do
    source_index = Keyword.get(opts, :source_index)

    Enum.any?(learned_commands, fn command ->
      command.control_type == control_type &&
        command.zone == zone &&
        command.source_index == source_index
    end)
  end

  defp format_hex_sequence_from_values(values) do
    values
    |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
    |> Enum.join(" ")
    |> String.upcase()
  end

end
