defmodule MqttLensWeb.Router do
  use MqttLensWeb, :router

  alias MqttLensWeb.Plugs.SecurityHeaders

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MqttLensWeb.Layouts, :root}
    plug :protect_from_forgery

    # A strict baseline (a literal map, so that it is visible to review tools).
    plug :put_secure_browser_headers, %{
      "content-security-policy" => "default-src 'none'; frame-ancestors 'none'",
      "strict-transport-security" => "max-age=63072000; includeSubDomains",
      "referrer-policy" => "no-referrer",
      "cross-origin-opener-policy" => "same-origin",
      "cross-origin-resource-policy" => "same-origin"
    }

    # The full policy with the public host and the Keycloak origin (runtime values).
    plug :secure_headers
  end

  defp secure_headers(conn, _opts) do
    put_secure_browser_headers(conn, SecurityHeaders.headers())
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MqttLensWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", MqttLensWeb do
  #   pipe_through :api
  # end
end
