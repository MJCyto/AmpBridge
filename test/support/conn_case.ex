defmodule AmpBridgeWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use AmpBridgeWeb, :verified_routes
      import Plug.Conn
      import Phoenix.LiveViewTest
      import AmpBridgeWeb.ConnCase
    end
  end

  setup tags do
    AmpBridgeWeb.ConnCase.setup_sandbox(tags)
    {:ok, conn: AmpBridgeWeb.Endpoint.build_conn()}
  end

  def setup_sandbox(_tags) do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AmpBridge.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AmpBridge.Repo, {:shared, self()})
  end
end
