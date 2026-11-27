defmodule AmpBridgeWeb.ZoneConfigComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "renders delete controls and an add-zone card" do
    html =
      render_component(&AmpBridgeWeb.ZoneConfigComponent.render/1,
        myself: "zone-config",
        form_data: %{"zone_count" => "2"},
        errors: %{},
        zones: [
          %{"name" => "Living Room", "available_sources" => [0]},
          %{"name" => "Bedroom", "available_sources" => [1]}
        ],
        sources: [%{"name" => "Wiim"}, %{"name" => "Zenbook"}],
        amp_id: 1
      )

    assert html =~ ~s(phx-click="delete_zone")
    assert html =~ "/images/trash.svg"
    assert html =~ ~s(x-show="confirming")
    assert html =~ "Delete zone?"
    assert html =~ "Cancel"
    assert html =~ ~s(phx-value-index="0")
    assert html =~ ~s(phx-value-index="1")
    assert html =~ ~s(phx-click="add_zone")
    assert html =~ "Add zone"
    assert html =~ ~s(x-show="open")
    assert html =~ "Sources (1)"
    refute html =~ "<details"
    refute html =~ "How many audio zones does your amplifier have?"
    refute html =~ "Zone 1:"
    assert html =~ ~s(placeholder="Zone 1 name")
  end
end
