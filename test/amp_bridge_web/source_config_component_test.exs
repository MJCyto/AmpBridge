defmodule AmpBridgeWeb.SourceConfigComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "renders compact source cards with zone multi-selects" do
    html =
      render_component(&AmpBridgeWeb.SourceConfigComponent.render/1,
        myself: "source-config",
        form_data: %{"source_count" => "1"},
        errors: %{},
        sources: [%{"name" => "Wiim"}],
        zones: [%{"name" => "Bedroom", "available_sources" => [0]}],
        amp_id: 1
      )

    assert html =~ "Zones (1)"
    assert html =~ ~s(name="source_config[sources][0][zones][]")
    assert html =~ ~s(phx-click="add_source")
    assert html =~ "/images/trash.svg"
    assert html =~ "Delete source?"
  end
end
