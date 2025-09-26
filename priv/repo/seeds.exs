# Script for populating the database with its default data.
#
# You can read the documentation for the Ecto.Query module for more info.

alias AmpBridge.Repo
alias AmpBridge.AudioDevice

# Create some sample audio devices
devices = [
  #  %{
  #    name: "Living Room Speaker",
  #    device_type: "speaker",
  #    room: "Living Room",
  #    ip_address: "192.168.1.100",
  #    port: 8080,
  #    is_active: true,
  #    settings: %{"volume": 75, "bass": 50, "treble": 50}
  #  },
  #  %{
  #    name: "Kitchen Receiver",
  #    device_type: "receiver",
  #    room: "Kitchen",
  #    ip_address: "192.168.1.101",
  #    port: 8081,
  #    is_active: true,
  #    settings: %{"input": "bluetooth", "volume": 60}
  #  },
  %{
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
]

Enum.each(devices, fn device_attrs ->
  %AudioDevice{}
  |> AudioDevice.changeset(device_attrs)
  |> Repo.insert!()
end)

IO.puts("Sample audio devices created successfully!")
