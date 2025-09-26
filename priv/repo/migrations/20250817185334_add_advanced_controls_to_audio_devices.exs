defmodule AmpBridge.Repo.Migrations.AddAdvancedControlsToAudioDevices do
  use Ecto.Migration

  def change do
    # Note: Since inputs and outputs are stored as JSON, we don't need to add new columns
    # The new fields (mute, power, input_source, balance, crossover_freq, phase) will be
    # automatically available in the JSON data when we update the schema and existing data
    # will continue to work with the new fields as optional values
  end
end
