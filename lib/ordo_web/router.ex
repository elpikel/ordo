defmodule OrdoWeb.Router do
  use OrdoWeb, :router

  import OrdoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OrdoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug OrdoWeb.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", OrdoWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Landing-page pilot signup: saves the email and notifies the team.
    post "/pilot", PageController, :pilot

    # Public one-click demo login (no password): logs in the seeded demo user.
    get "/demo", UserSessionController, :enter_demo

    # Language switch (persists choice in session, redirects back).
    get "/locale/:locale", LocaleController, :update

    # Static, bilingual blog (SEO). Feed routes before :slug so they aren't captured.
    get "/blog", BlogController, :index
    get "/blog/feed.xml", BlogController, :feed
    get "/blog/:slug", BlogController, :show
    get "/en/blog", BlogController, :index
    get "/en/blog/feed.xml", BlogController, :feed
    get "/en/blog/:slug", BlogController, :show
    get "/sitemap.xml", SitemapController, :index
    get "/robots.txt", SitemapController, :robots
  end

  scope "/", OrdoWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :tenant_app,
      on_mount: [OrdoWeb.Locale, {OrdoWeb.UserAuth, :require_authenticated}] do
      live "/inbox", InboxLive
      live "/inbox/:id", InboxLive
      live "/settings", TenantSettingsLive
    end

    # Google Business Profile connect (OAuth redirect flow — controller, not live).
    get "/oauth/google/authorize", GoogleOAuthController, :authorize
    get "/oauth/google/callback", GoogleOAuthController, :callback
  end

  # Analytics event proxy to avoid ad blockers (no pipeline: POST /api/event must skip CSRF).
  # The tracking script itself is a vendored static file at priv/static/js/stats.js.
  scope "/", OrdoWeb do
    post "/api/event", AnalyticsController, :event
  end

  # Other scopes may use custom stacks.
  # scope "/api", OrdoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ordo, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OrdoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", OrdoWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [OrdoWeb.Locale, {OrdoWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", OrdoWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [OrdoWeb.Locale, {OrdoWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
