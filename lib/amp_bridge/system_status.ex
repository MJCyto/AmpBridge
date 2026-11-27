defmodule AmpBridge.SystemStatus do
  alias AmpBridge.Devices

  def fetch do
    %{
      database_connected: database_connected(),
      mqtt_connected: mqtt_connected(),
      mqtt_broker: "localhost:1883",
      mqtt_message_count: 0,
      system_uptime: format_uptime(system_uptime_seconds()),
      memory_usage: memory_usage(),
      last_command_time: "None",
      last_command_details: "No commands sent",
      error_count: 0
    }
  end

  defp database_connected do
    try do
      is_list(Devices.list_devices())
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end

  defp mqtt_connected do
    is_pid(Process.whereis(AmpBridge.MQTTClient))
  end

  defp system_uptime_seconds do
    {milliseconds, _} = :erlang.statistics(:wall_clock)
    div(milliseconds, 1000)
  rescue
    _ -> 0
  end

  defp memory_usage do
    total_mb = :erlang.memory(:total) / 1024 / 1024
    "#{Float.round(total_mb, 1)} MB"
  rescue
    _ -> "Unknown"
  end

  defp format_uptime(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end
end
