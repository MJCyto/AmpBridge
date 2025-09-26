defmodule AmpBridgeWeb.PageWrapper do
  use AmpBridgeWeb, :html

  import Phoenix.Component, only: [attr: 3, slot: 2, render_slot: 1, sigil_H: 2, assign: 3]
  import AmpBridgeWeb.NavBar

  @doc """
  Generates a page label from a given path.

  ## Examples

      iex> page_label_from_path("/")
      "Dashboard"

      iex> page_label_from_path("/serial_analysis")
      "Serial Analysis"

      iex> page_label_from_path("/command_learning")
      "Command Learning"
  """
  def page_label_from_path(path) when is_binary(path) do
    case path do
      "/" ->
        "Dashboard"

      path ->
        path
        |> String.split("/")
        |> Enum.at(1)
        |> case do
          nil ->
            "AmpBridge"

          first_part ->
            first_part
            |> String.split("_")
            |> Enum.map(&String.capitalize/1)
            |> Enum.join(" ")
        end
    end
  end

  attr :class, :string, default: "", doc: "Additional CSS classes for the main content container"
  attr :uri, :string, doc: "URI to parse for current path and page label generation"

  slot :header_actions, doc: "Optional actions to display in the page header"
  slot :inner_block, required: true, doc: "The main page content"

  def page_wrapper(assigns) do
    current_path = URI.parse(assigns.uri).path

    assigns =
      assigns
      |> assign(:current_path, current_path)
      |> assign(:page_label, page_label_from_path(current_path))

    ~H"""
    <div class="w-screen h-screen">
      <.nav_bar current_path={@current_path} />

      <div class={[
        "overflow-y-auto h-screen transition-all duration-200",
        if(@current_path == "/init", do: "ml-0", else: "")
      ]} x-bind:style={if(@current_path == "/init", do: "", else: "navExpanded ? 'margin-left: 16rem;' : 'margin-left: 4rem;'")} style={if(@current_path == "/init", do: "", else: "margin-left: 4rem;")}>
        <div class="px-6 py-8 w-full max-w-7xl mx-auto">
          <div class={["", @class]}>
            <%= render_slot(@inner_block) %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
