# Script for seeding the database during Docker build
# This version doesn't require the full application to be started

alias AmpBridge.Repo
alias AmpBridge.AudioDevice

# Start the repo manually
{:ok, _} = AmpBridge.Repo.start_link()

# Create sample audio device
device_attrs = %{
  name: "Amplifier",
  device_type: "matrix_amplifier",
  is_active: true,
  inputs: [
    %{
      name: "WIIM Pro",
      volume: 80,
      input_source: "digital"
    },
    %{
      name: "Input 2",
      volume: 70,
      input_source: "analog"
    }
  ],
  outputs: [
    %{
      name: "Bedroom Left",
      volume: 50,
      bass: 50,
      treble: 50,
      mute: false,
      power: true,
      balance: 0,
      phase: false
    },
    %{
      name: "Bedroom Right",
      volume: 50,
      bass: 50,
      treble: 50,
      mute: false,
      power: true,
      balance: 0,
      phase: false
    },
    %{
      name: "Bathroom Left",
      volume: 45,
      bass: 45,
      treble: 45,
      mute: false,
      power: true,
      balance: -10,
      phase: false
    },
    %{
      name: "Bathroom Right",
      volume: 45,
      bass: 45,
      treble: 45,
      mute: false,
      power: true,
      balance: 10,
      phase: false
    }
  ]
}

%AudioDevice{}
|> AudioDevice.changeset(device_attrs)
|> Repo.insert!()

IO.puts("Sample audio device created successfully!")
