defmodule AmpBridge.SerialCommand do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:zone_index, :integer, autogenerate: false}
  schema "serial_commands" do
    field(:mute, :string, default: "[]")
    field(:unmute, :string, default: "[]")

    timestamps()
  end

  def changeset(serial_command, attrs) do
    serial_command
    |> cast(attrs, [:zone_index, :mute, :unmute])
    |> validate_required([:zone_index])
    |> validate_inclusion(:zone_index, 0..7)
  end
end
