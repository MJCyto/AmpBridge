defmodule AmpBridge.Repo do
  use Ecto.Repo,
    otp_app: :amp_bridge,
    adapter: Ecto.Adapters.SQLite3
end
