defmodule AmpBridge.CommandQueue.Command do
  @moduledoc """
  Represents a command to be sent to the amplifier.
  """

  defstruct [
    :id,           # Unique identifier for the command
    :type,         # Command type (:volume, :mute, :unmute, :source, etc.)
    :zone,         # Zone number (1-based)
    :params,       # Command parameters (e.g., %{volume: 50})
    :data,         # Binary data to send over serial
    :replaceable,  # Whether this command can be replaced by a newer one
    :priority      # Command priority (:high, :normal, :low)
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    type: atom(),
    zone: integer(),
    params: map(),
    data: binary(),
    replaceable: boolean(),
    priority: atom()
  }

  @doc """
  Create a new command.
  """
  def new(id, type, zone, params, data, opts \\ []) do
    %__MODULE__{
      id: id,
      type: type,
      zone: zone,
      params: params,
      data: data,
      replaceable: Keyword.get(opts, :replaceable, false),
      priority: Keyword.get(opts, :priority, :normal)
    }
  end

  @doc """
  Create a volume command.
  Note: zones are 0-indexed in the UI but 1-indexed in the amp protocol.
  """
  def volume(zone, volume_level, data) do
    new(
      "vol_#{zone}_#{volume_level}",
      :volume,
      zone,
      %{volume: volume_level},
      data,
      replaceable: true,
      priority: :normal
    )
  end

  @doc """
  Create a mute command.
  Note: zones are 0-indexed in the UI but 1-indexed in the amp protocol.
  """
  def mute(zone, muted, data) do
    new(
      "mute_#{zone}_#{if muted, do: "on", else: "off"}",
      :mute,
      zone,
      %{muted: muted},
      data,
      replaceable: false,
      priority: :high
    )
  end

  @doc """
  Create a source command.
  Note: zones are 0-indexed in the UI but 1-indexed in the amp protocol.
  """
  def source(zone, source, data) do
    new(
      "src_#{zone}_#{source}",
      :source,
      zone,
      %{source: source},
      data,
      replaceable: false,
      priority: :normal
    )
  end
end
