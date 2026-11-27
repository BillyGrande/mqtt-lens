defmodule MqttLensWeb.OpsEndpoint do
  @moduledoc """
  Second endpoint on :9090 for health, readiness and metrics. It has no
  router, no static files, no session and no sockets.
  """
  use Phoenix.Endpoint, otp_app: :mqtt_lens

  plug MqttLensWeb.Plugs.Ops
end
