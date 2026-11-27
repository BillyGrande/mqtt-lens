defmodule MqttLensWeb.OpsEndpointTest do
  @moduledoc """
  The ops endpoint (ml-1a7.2, criterion 3): /healthz and /readyz on :9090
  return 200 and are not routed on the main endpoint (:4000).

  Specs: architecture/overview.md#architecture, architecture/observability.md,
  features/routes.md, features/web-security.md (OpsEndpoint sends no HTML).
  """
  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint MqttLensWeb.OpsEndpoint

  @ops_paths ~w(/healthz /readyz /metrics)

  describe "MqttLensWeb.OpsEndpoint" do
    test "is started by the application" do
      pid = Process.whereis(MqttLensWeb.OpsEndpoint)

      assert is_pid(pid) and Process.alive?(pid)
    end

    test "listens on port 9090" do
      config = Application.get_env(:mqtt_lens, MqttLensWeb.OpsEndpoint, [])

      assert get_in(config, [:http, :port]) == 9090
    end

    for path <- @ops_paths do
      @path path

      test "GET #{path} returns 200 and no HTML" do
        conn = get(build_conn(), @path)

        assert conn.status == 200

        for content_type <- get_resp_header(conn, "content-type") do
          refute content_type =~ "text/html"
        end
      end
    end

    test "does not serve the main router" do
      assert status_of(fn -> get(build_conn(), "/") end) == 404
    end

    test "does not serve static files" do
      assert status_of(fn -> get(build_conn(), "/robots.txt") end) == 404
    end

    test "returns 404 for an unknown path" do
      assert status_of(fn -> get(build_conn(), "/no-such-path") end) == 404
    end
  end

  describe "MqttLensWeb.Endpoint (:4000)" do
    for path <- @ops_paths do
      @path path

      test "does not route #{path}" do
        assert status_of(fn ->
                 dispatch(build_conn(), MqttLensWeb.Endpoint, :get, @path, nil)
               end) == 404
      end
    end
  end

  # The status of a sent response, or the Plug status of the exception that
  # the endpoint raised after it sent the error page.
  defp status_of(fun) do
    fun.().status
  rescue
    exception -> Plug.Exception.status(exception)
  end
end
