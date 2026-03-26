defmodule AmpBridge.StartupZoneDefaultsTest do
  use ExUnit.Case, async: false

  alias AmpBridge.{AudioDevice, Devices, Repo, StartupZoneDefaults}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "normalized_off_unmuted_attrs sets sources nil and mutes false, preserves volumes" do
    device =
      case Repo.get(AudioDevice, 1) do
        nil ->
          {:ok, d} =
            Devices.create_device(%{
              name: "T",
              model: "M",
              manufacturer: "X",
              zones: %{"0" => %{"name" => "Z0"}, "1" => %{"name" => "Z1"}},
              source_states: %{"0" => "Source 1", "1" => "Source 2"},
              mute_states: %{"0" => true, "1" => true},
              volume_states: %{"0" => 33, "1" => 44}
            })

          d

        d ->
          {:ok, d} =
            Devices.update_device(d, %{
              zones: %{"0" => %{"name" => "Z0"}, "1" => %{"name" => "Z1"}},
              source_states: %{"0" => "Source 1", "1" => "Source 2"},
              mute_states: %{"0" => true, "1" => true},
              volume_states: %{"0" => 33, "1" => 44}
            })

          d
      end

    assert {:ok, attrs} = StartupZoneDefaults.normalized_off_unmuted_attrs(device)
    assert attrs.source_states["0"] == nil
    assert attrs.source_states["1"] == nil
    assert attrs.mute_states["0"] == false
    assert attrs.mute_states["1"] == false

    {:ok, updated} = Devices.update_device(device, attrs)
    assert updated.volume_states["0"] == 33
    assert updated.volume_states["1"] == 44
  end

  test "normalized_off_unmuted_attrs returns :skip when no zones" do
    {:ok, device} =
      Devices.create_device(%{
        name: "Empty",
        model: "M",
        manufacturer: "X",
        zones: %{},
        source_states: %{},
        mute_states: %{},
        volume_states: %{}
      })

    assert :skip = StartupZoneDefaults.normalized_off_unmuted_attrs(device)
  end
end
