defmodule MqttLensWeb.Plugs.Ops do
  @moduledoc """
  Routes of the ops endpoint (port 9090): /healthz, /readyz and a /metrics
  placeholder. Everything else is 404. No HTML is sent.
  """
  use Plug.Router

  plug :match
  plug :dispatch

  get "/healthz" do
    send_text(conn, "ok\n")
  end

  get "/readyz" do
    send_text(conn, "ok\n")
  end

  # Placeholder; the content comes with the observability task.
  get "/metrics" do
    send_text(conn, "")
  end

  match _ do
    send_text(conn, "not found\n", 404)
  end

  defp send_text(conn, body, status \\ 200) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end
end
