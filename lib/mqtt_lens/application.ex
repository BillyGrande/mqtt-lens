defmodule MqttLens.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MqttLensWeb.Telemetry,
      {Phoenix.PubSub, name: MqttLens.PubSub},
      # Start a worker by calling: MqttLens.Worker.start_link(arg)
      # {MqttLens.Worker, arg},
      # Start to serve requests, typically the last entry
      MqttLensWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MqttLens.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MqttLensWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
