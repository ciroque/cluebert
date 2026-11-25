defmodule CluebertWeb.Router do
  use CluebertWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CluebertWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", CluebertWeb do
    pipe_through :browser

    live "/", HomeLive
  end

  # LiveDashboard is dev-only; it has no authentication.
  if Application.compile_env(:cluebert, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CluebertWeb.Telemetry
    end
  end
end
