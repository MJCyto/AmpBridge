defmodule AmpBridgeWeb.Common.Slider do
  use AmpBridgeWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center">
      <div class="flex-1 text-sm">
        <label for={@id} class="sr-only"><%= @label %></label>
        <div class="relative">
          <input
            type="range"
            name={@name}
            id={@id}
            value={@value}
            min={@min}
            max={@max}
            step={@step}
            class="w-full h-2 rounded-lg appearance-none cursor-pointer focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-opacity-50"
          />
        </div>
      </div>
      <%= if @value do %>
        <div class="flex-1 ml-3 text-right text-sm text-neutral-600">
          <p><%= @value %></p>
        </div>
      <% end %>
    </div>
    """
  end
end
