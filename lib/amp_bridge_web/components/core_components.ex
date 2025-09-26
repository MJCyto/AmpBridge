defmodule AmpBridgeWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component

  @doc """
  Renders SVG icons with proper color inheritance.
  Uses CSS mask approach for better color control.

  ## Examples

      <.icon url="/images/adjustments-vertical.svg" class="w-6 h-6 text-white" />
      <.icon url="/images/book-open.svg" class="w-5 h-5 text-gray-500" />
  """
  attr :url, :string, required: true, doc: "the URL path to an external SVG file"
  attr :class, :string, default: "size-4"
  attr :rest, :global, doc: "arbitrary HTML attributes to add to the span element"

  def icon(%{url: url} = assigns) when is_binary(url) do
    assigns =
      assign(
        assigns,
        :style,
        "mask: url('#{url}') no-repeat center; -webkit-mask: url('#{url}') no-repeat center; background-color: currentColor; display: inline-block;"
      )

    ~H"""
    <span
      class={@class}
      style={@style}
      {@rest}
    >
    </span>
    """
  end
end
