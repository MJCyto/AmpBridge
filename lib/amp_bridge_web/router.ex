defmodule AmpBridgeWeb.Router do
  use AmpBridgeWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {AmpBridgeWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", AmpBridgeWeb do
    pipe_through(:browser)

    live("/", HomeLive.Index)
    live("/init", InitLive)
    live("/sources", SourceSetupLive)
    live("/zones", ZoneSetupLive)
    live("/serial-config", SerialStepLive)
    live("/serial-analysis", SerialAnalysisLive.Index)
    live("/eth-diagram", EthDiagramLive.Index)
    live("/command-learning", CommandLearningLive)
  end

  scope "/api", AmpBridgeWeb do
    pipe_through(:api)

    # Health check endpoint
    get("/health", ZoneController, :health)

    # Zone management endpoints
    get("/zones", ZoneController, :index)
    get("/zones/:id", ZoneController, :show)
    post("/zones/:id/volume", ZoneController, :set_volume)
    post("/zones/:id/mute", ZoneController, :toggle_mute)
    post("/zones/:id/source", ZoneController, :set_source)
  end

  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: AmpBridgeWeb.Telemetry)
    end
  end
end
