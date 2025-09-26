defmodule AmpBridge.LearnedCommand do
  @moduledoc """
  Schema for learned amplifier commands.

  Stores command sequences and response patterns learned from user interactions
  during the command learning phase of system initialization.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "learned_commands" do
    field(:control_type, :string)
    field(:zone, :integer)
    field(:source_index, :integer)
    field(:volume_level, :integer)
    field(:command_sequence, :binary)
    field(:response_pattern, :binary)
    field(:is_active, :boolean, default: true)
    field(:learned_at, :naive_datetime)
    field(:last_used, :naive_datetime)

    belongs_to(:device, AmpBridge.AudioDevice)

    timestamps()
  end

  @doc false
  def changeset(learned_command, attrs) do
    learned_command
    |> cast(attrs, [
      :device_id,
      :control_type,
      :zone,
      :source_index,
      :volume_level,
      :command_sequence,
      :response_pattern,
      :is_active,
      :learned_at,
      :last_used
    ])
    |> validate_required([
      :device_id,
      :control_type,
      :zone,
      :command_sequence,
      :learned_at
    ])
    |> validate_inclusion(:control_type, [
      "mute",
      "unmute",
      "volume_up",
      "volume_down",
      "set_volume",
      "change_source",
      "turn_off"
    ])
    |> validate_number(:zone, greater_than_or_equal_to: 0, less_than: 17)
    |> validate_number(:volume_level, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:source_index, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:device_id)
    |> unique_constraint([:device_id, :control_type, :zone, :source_index, :volume_level],
      name: :unique_learned_command
    )
  end

  @doc """
  Create a changeset for a new learned command.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:learned_at, NaiveDateTime.utc_now())
  end

  @doc """
  Update the last_used timestamp for a command.
  """
  def update_last_used_changeset(learned_command) do
    learned_command
    |> changeset(%{})
    |> put_change(:last_used, NaiveDateTime.utc_now())
  end
end
