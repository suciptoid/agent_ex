defmodule AppWeb.Router do
  use AppWeb, :router

  import AppWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :active_organization_required do
    plug :require_active_organization
  end

  scope "/", AppWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", AppWeb do
  #   pipe_through :api
  # end

  # Gateway webhook endpoint — no CSRF, no session
  scope "/gateway", AppWeb do
    pipe_through :api

    post "/webhook/:gateway_id", GatewayWebhookController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", AppWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/organizations/switch/:id", OrganizationSessionController, :update
    post "/users/update-password", UserSessionController, :update_password

    live_session :require_authenticated_user,
      on_mount: [{AppWeb.UserAuth, :require_authenticated}] do
      live "/organizations/select", OrganizationLive.Select, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", AppWeb do
    pipe_through [:browser, :require_authenticated_user, :active_organization_required]

    live_session :require_active_organization,
      on_mount: [{AppWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/providers", ProviderLive.Index, :index
      live "/providers/new", ProviderLive.Index, :new
      live "/providers/:id/edit", ProviderLive.Index, :edit
      live "/tools/list", ToolLive.Index, :index
      live "/tools/create", ToolLive.Create, :new
      live "/tools/:id/edit", ToolLive.Create, :edit
      live "/agents", AgentLive.Index, :index
      live "/agents/new", AgentLive.New, :new
      live "/agents/:id/edit", AgentLive.Index, :edit
      live "/chat", ChatLive.Index, :index
      live "/chat/:id", ChatLive.Show, :show
      live "/gateways", GatewayLive.Index, :index
      live "/gateways/new", GatewayLive.Index, :new
      live "/gateways/:id/edit", GatewayLive.Index, :edit
    end
  end

  scope "/", AppWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{AppWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
