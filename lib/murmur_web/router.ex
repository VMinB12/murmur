defmodule MurmurWeb.Router do
  use MurmurWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MurmurWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' ws: wss:;"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MurmurWeb do
    pipe_through :browser

    live "/", WorkspaceListLive
    live "/workspaces", WorkspaceListLive
    live "/workspaces/:id", WorkspaceLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", MurmurWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:murmur, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MurmurWeb.Telemetry
    end
  end
end
