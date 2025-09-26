defmodule AmpBridge.AudioDevice.InputOutput do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:name, :string)
    field(:volume, :integer)
    field(:bass, :integer)
    field(:treble, :integer)
    field(:mute, :boolean, default: false)
    field(:power, :boolean, default: true)
    field(:input_source, :string)
    # -50 to +50 for stereo balance
    field(:balance, :integer)
    # Crossover frequency in Hz
    field(:crossover_freq, :integer)
    # Phase inversion
    field(:phase, :boolean, default: false)
    # New: left, right, or mono
    field(:channel_type, :string, default: "mono")
    # New: reference to zone if assigned
    field(:zone_id, :string)
  end

  def changeset(input_output, attrs) do
    input_output
    |> cast(attrs, [
      :name,
      :volume,
      :bass,
      :treble,
      :mute,
      :power,
      :input_source,
      :balance,
      :crossover_freq,
      :phase,
      :channel_type,
      :zone_id
    ])
    |> validate_required([:name])
    |> validate_inclusion(:channel_type, ["left", "right", "mono"])
    |> validate_number(:volume, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:bass, greater_than_or_equal_to: -50, less_than_or_equal_to: 50)
    |> validate_number(:treble, greater_than_or_equal_to: -50, less_than_or_equal_to: 50)
    |> validate_number(:balance, greater_than_or_equal_to: -50, less_than_or_equal_to: 50)
    |> validate_number(:crossover_freq,
      greater_than_or_equal_to: 20,
      less_than_or_equal_to: 20000
    )
  end
end

defmodule AmpBridge.AudioDevice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_devices" do
    field(:name, :string)
    field(:ip_address, :string)
    field(:port, :integer)
    field(:is_active, :boolean, default: true)
    field(:settings, :map, default: %{})
    embeds_many(:inputs, AmpBridge.AudioDevice.InputOutput, on_replace: :delete)
    embeds_many(:outputs, AmpBridge.AudioDevice.InputOutput, on_replace: :delete)
    # New: sources, zones and speaker groups as JSON fields
    field(:sources, :map, default: %{})
    field(:zones, :map, default: %{})
    field(:speaker_groups, :map, default: %{})
    # Zone state tracking
    field(:mute_states, :map, default: %{})
    field(:source_states, :map, default: %{})
    field(:volume_states, :map, default: %{})
    # USB adapter assignments and settings
    field(:adapter_1_device, :string)
    field(:adapter_1_settings, :map, default: %{})
    field(:adapter_2_device, :string)
    field(:adapter_2_settings, :map, default: %{})
    # Auto-detection tracking
    field(:auto_detection_complete, :boolean, default: false)
    field(:adapter_1_name, :string)
    field(:adapter_2_name, :string)
    field(:adapter_1_role, :string)
    field(:adapter_2_role, :string)
    # Command learning tracking
    field(:command_learning_complete, :boolean, default: false)

    timestamps()
  end

  @doc false
  def changeset(audio_device, attrs) do
    audio_device
    |> cast(attrs, [
      :name,
      :ip_address,
      :port,
      :is_active,
      :settings,
      :sources,
      :zones,
      :speaker_groups,
      :mute_states,
      :source_states,
      :volume_states,
      :adapter_1_device,
      :adapter_1_settings,
      :adapter_2_device,
      :adapter_2_settings,
      :auto_detection_complete,
      :adapter_1_name,
      :adapter_2_name,
      :adapter_1_role,
      :adapter_2_role,
      :command_learning_complete
    ])
    |> cast_embed(:inputs, with: &AmpBridge.AudioDevice.InputOutput.changeset/2)
    |> cast_embed(:outputs, with: &AmpBridge.AudioDevice.InputOutput.changeset/2)
    |> validate_required([:name])
    |> validate_number(:port, greater_than: 0, less_than: 65536)
  end
end
