import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/mqtt_lens start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :mqtt_lens, MqttLensWeb.Endpoint, server: true
  config :mqtt_lens, MqttLensWeb.OpsEndpoint, server: true
end

config :mqtt_lens, MqttLensWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :mqtt_lens, MqttLensWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/mqtt_lens_web/router\.ex$"E,
        ~r"lib/mqtt_lens_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # Fail closed: a missing or bad setting or secret raises MqttLens.Config.Error
  # and the release does not start. Non-secret settings come from
  # mqtt-lens.toml (ConfigMap), secrets from files (Kubernetes Secret).
  settings =
    "MQTT_LENS_CONFIG"
    |> System.get_env("/etc/mqtt-lens/mqtt-lens.toml")
    |> MqttLens.Config.read_settings!()

  app_config =
    "MQTT_LENS_SECRETS_DIR"
    |> System.get_env("/run/secrets/mqtt-lens")
    |> then(&MqttLens.Config.load!(settings, &1))

  config :mqtt_lens, :oidc_origin, app_config.issuer_origin

  config :mqtt_lens, MqttLensWeb.Endpoint,
    url: [host: app_config.public_host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    check_origin: app_config.check_origin,
    secret_key_base: app_config.secret_key_base,
    session_signing_salt: app_config.signing_salt,
    session_encryption_salt: app_config.encryption_salt,
    live_view: [signing_salt: app_config.signing_salt]

  config :mqtt_lens, MqttLensWeb.OpsEndpoint, http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :mqtt_lens, MqttLensWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :mqtt_lens, MqttLensWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
