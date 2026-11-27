defmodule MqttLensWeb.PageController do
  use MqttLensWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
