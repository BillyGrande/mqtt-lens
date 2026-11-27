defmodule MqttLens.ConfigReview2Test do
  @moduledoc """
  Review round 2 of ml-1a7.2 (PR #19), finding ml-1a7.2.10.

  A one-letter host in `check_origin` or in the OIDC issuer must never crash
  the config check with another exception. A bad config raises
  `MqttLens.Config.Error` and lists all errors. A valid one-letter host (for
  example a compose service name) is accepted.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  defp write_secrets(dir) do
    secrets_dir = Path.join(dir, "secrets")
    File.mkdir_p!(secrets_dir)
    File.write!(Path.join(secrets_dir, "secret_key_base"), String.duplicate("k", 64) <> "-value")
    File.write!(Path.join(secrets_dir, "signing_salt"), "signing-salt-from-file")
    File.write!(Path.join(secrets_dir, "encryption_salt"), "encryption-salt-from-file")
    secrets_dir
  end

  defp settings(overrides) do
    Map.merge(
      %{
        "public_host" => "lens.example.org",
        "check_origin" => ["https://lens.example.org"],
        "oidc" => %{"issuer" => "https://id.example.org/realms/lens"}
      },
      overrides
    )
  end

  test "a one-letter host in check_origin raises Config.Error", %{tmp_dir: dir} do
    error =
      assert_raise MqttLens.Config.Error, fn ->
        MqttLens.Config.load!(
          settings(%{"check_origin" => ["https://a"]}),
          write_secrets(dir)
        )
      end

    assert Exception.message(error) =~ "check_origin"
  end

  test "a one-letter host in the issuer raises Config.Error with the other errors", %{
    tmp_dir: dir
  } do
    error =
      assert_raise MqttLens.Config.Error, fn ->
        MqttLens.Config.load!(
          settings(%{
            "check_origin" => ["http://x"],
            "oidc" => %{"issuer" => "https://k/realms/x"}
          }),
          write_secrets(dir)
        )
      end

    assert Exception.message(error) =~ "check_origin"
  end

  test "a valid one-letter host is accepted", %{tmp_dir: dir} do
    assert %{issuer_origin: "https://k"} =
             MqttLens.Config.load!(
               settings(%{
                 "public_host" => "a",
                 "check_origin" => ["https://a", "https://a:8443"],
                 "oidc" => %{"issuer" => "https://k/realms/x"}
               }),
               write_secrets(dir)
             )

    assert %{issuer_origin: "https://k:8443"} =
             MqttLens.Config.load!(
               settings(%{"oidc" => %{"issuer" => "https://k:8443/realms/x"}}),
               write_secrets(dir)
             )
  end
end
