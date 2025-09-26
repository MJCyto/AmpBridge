defmodule AmpBridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :amp_bridge,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {AmpBridge.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.0"},
      {:phoenix_live_view, "~> 0.20.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.21.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      # Hardware management dependencies
      # For serial communication
      {:circuits_uart, "~> 1.4"},
      # Decimal library for precise decimal arithmetic
      {:decimal, "~> 2.0"},
      # MQTT client for Home Assistant integration
      {:tortoise, "~> 0.10"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      dev: ["dev"],
      server: ["copy.static", "phx.server"],
      kill: ["cmd pkill -9 -f 'beam.smp' && pkill -9 -f 'mix'"],
      "assets.setup": ["cmd npm install --prefix assets"],
      "assets.build": ["cmd npm run deploy --prefix assets", "copy.static"],
      "assets.watch": ["cmd npm run watch --prefix assets"],
      "copy.static": [
        "cmd mkdir -p priv/static/assets/icons && cp -r assets/static/icons/* priv/static/assets/icons/"
      ]
    ]
  end
end
