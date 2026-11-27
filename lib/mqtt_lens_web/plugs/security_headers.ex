defmodule MqttLensWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Web-security response headers (spec: features/web-security.md).

  The endpoint runs this plug before anything else, so error pages from
  `Plug.Parsers` (400, 413, 415) and 404 responses carry the headers too.
  `headers/0` is also used by the router's `put_secure_browser_headers/2`.
  """
  @behaviour Plug

  @doc """
  `@before_compile` hook for an endpoint. It wraps `call/2` outside of the
  Phoenix error rendering, because `RenderErrors` renders with the conn from
  the start of `call/2`.
  """
  defmacro __before_compile__(_env) do
    plug = __MODULE__

    quote do
      defoverridable call: 2

      def call(conn, opts) do
        conn
        |> unquote(plug).call([])
        |> super(opts)
      end
    end
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Enum.reduce(headers(), conn, fn {name, value}, conn ->
      Plug.Conn.put_resp_header(conn, name, value)
    end)
  end

  @doc "The header map. The CSP depends on the public host and the Keycloak origin."
  @spec headers() :: %{String.t() => String.t()}
  def headers do
    %{
      "content-security-policy" => csp(),
      "strict-transport-security" => "max-age=63072000; includeSubDomains",
      "x-content-type-options" => "nosniff",
      "referrer-policy" => "no-referrer",
      "cross-origin-opener-policy" => "same-origin",
      "cross-origin-resource-policy" => "same-origin",
      "permissions-policy" => "camera=(), microphone=(), geolocation=()",
      # HTML and error responses. Plug.Static replaces it for static files.
      "cache-control" => "no-store"
    }
  end

  defp csp do
    host = MqttLensWeb.Endpoint.host()
    keycloak = Application.fetch_env!(:mqtt_lens, :oidc_origin)

    Enum.join(
      [
        "default-src 'none'",
        "script-src 'self'",
        "style-src 'self'",
        "img-src 'self' data:",
        "connect-src 'self' wss://#{host}",
        "font-src 'self'",
        "base-uri 'none'",
        "form-action 'self' #{keycloak}",
        "frame-ancestors 'none'"
      ],
      "; "
    )
  end
end
