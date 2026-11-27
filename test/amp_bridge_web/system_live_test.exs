defmodule AmpBridgeWeb.SystemLiveTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "renders system status cards" do
    html =
      render_component(&AmpBridgeWeb.SystemLive.render/1,
        uri: "/system",
        adapter_1_connected: true,
        adapter_2_connected: false,
        database_connected: true,
        mqtt_connected: false,
        mqtt_broker: "localhost:1883",
        mqtt_message_count: 0,
        system_uptime: "1m",
        memory_usage: "10 MB",
        last_command_details: "No commands sent",
        error_count: 0,
        device_count: 1
      )

    assert html =~ "System"
    assert html =~ "Serial Adapters"
    assert html =~ "Database"
    assert html =~ "MQTT"
    assert html =~ ~s(phx-click="refresh_status")
  end
end
