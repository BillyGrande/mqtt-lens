defmodule MqttLens.ConfigTest do
  @moduledoc """
  Fail-closed config validation (ml-1a7.2, criterion 2; ml-1a7.1.8).

  Specs: architecture/deployment.md#configuration-and-secrets, features/sessions.md.

  Contract under test:

    * `MqttLens.Config.load!(settings, secrets_dir)` validates the non-secret
      settings and reads the secrets from files. It returns a map and raises
      `MqttLens.Config.Error` with a clear message on bad config.
    * `settings` is the parsed `mqtt-lens.toml` (string keys):

          %{
            "public_host" => "lens.example.org",
            "check_origin" => ["https://lens.example.org"],
            "oidc" => %{"issuer" => "https://id.example.org/realms/lens"}
          }

    * `secrets_dir` holds one file for each secret: `secret_key_base`,
      `signing_salt`, `encryption_salt`.
    * In prod, `config/runtime.exs` calls the validation, so bad config stops
      startup with `MqttLens.Config.Error`.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @secret_key_base String.duplicate("k", 64) <> "-secret-key-base-value"
  @signing_salt "signing-salt-from-file"
  @encryption_salt "encryption-salt-from-file"

  @project_root Path.expand("../..", __DIR__)

  defp valid_settings do
    %{
      "public_host" => "lens.example.org",
      "check_origin" => ["https://lens.example.org"],
      "oidc" => %{"issuer" => "https://id.example.org/realms/lens"}
    }
  end

  defp write_secrets(dir, overrides \\ %{}) do
    %{
      "secret_key_base" => @secret_key_base,
      "signing_salt" => @signing_salt,
      "encryption_salt" => @encryption_salt
    }
    |> Map.merge(overrides)
    |> Enum.each(fn
      {_name, :absent} -> :ok
      {name, content} -> File.write!(Path.join(dir, name), content)
    end)

    dir
  end

  defp load_error(settings, secrets_dir) do
    error =
      assert_raise MqttLens.Config.Error, fn ->
        MqttLens.Config.load!(settings, secrets_dir)
      end

    Exception.message(error)
  end

  describe "valid config" do
    test "returns the secrets read from the secret files", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)

      assert %{
               secret_key_base: @secret_key_base,
               signing_salt: @signing_salt,
               encryption_salt: @encryption_salt,
               check_origin: ["https://lens.example.org"]
             } = MqttLens.Config.load!(valid_settings(), secrets_dir)
    end

    test "accepts an exact https origin with a port", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)
      settings = %{valid_settings() | "check_origin" => ["https://lens.example.org:8443"]}

      assert %{check_origin: ["https://lens.example.org:8443"]} =
               MqttLens.Config.load!(settings, secrets_dir)
    end
  end

  describe "missing secret stops startup" do
    for name <- ~w(secret_key_base signing_salt encryption_salt) do
      @name name

      test "when the #{name} file is absent", %{tmp_dir: dir} do
        secrets_dir = write_secrets(dir, %{@name => :absent})

        assert load_error(valid_settings(), secrets_dir) =~ @name
      end

      test "when the #{name} file is empty", %{tmp_dir: dir} do
        secrets_dir = write_secrets(dir, %{@name => ""})

        assert load_error(valid_settings(), secrets_dir) =~ @name
      end
    end

    test "when the secrets directory does not exist", %{tmp_dir: dir} do
      message = load_error(valid_settings(), Path.join(dir, "no-such-dir"))

      assert message =~ ~r/secret/i
    end

    test "when secret_key_base is shorter than 64 bytes, without the value in the message",
         %{tmp_dir: dir} do
      short = "short-secret-value-0123456789"
      secrets_dir = write_secrets(dir, %{"secret_key_base" => short})

      message = load_error(valid_settings(), secrets_dir)

      assert message =~ "secret_key_base"
      refute message =~ short
    end
  end

  describe "OIDC issuer" do
    test "an http:// issuer stops startup", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)
      settings = put_in(valid_settings(), ["oidc", "issuer"], "http://id.example.org/realms/lens")

      message = load_error(settings, secrets_dir)

      assert message =~ "issuer"
      assert message =~ "https"
    end

    test "an issuer with no scheme stops startup", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)
      settings = put_in(valid_settings(), ["oidc", "issuer"], "id.example.org/realms/lens")

      assert load_error(settings, secrets_dir) =~ "issuer"
    end

    test "an https:// issuer with no host stops startup", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)
      settings = put_in(valid_settings(), ["oidc", "issuer"], "https://")

      assert load_error(settings, secrets_dir) =~ "issuer"
    end

    test "a missing issuer stops startup", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)
      settings = %{valid_settings() | "oidc" => %{}}

      assert load_error(settings, secrets_dir) =~ "issuer"
    end
  end

  describe "check_origin that is not an exact https:// origin stops startup" do
    for {label, value} <- [
          {"http scheme", ["http://lens.example.org"]},
          {"wildcard host", ["https://*.example.org"]},
          {"scheme-less origin", ["//lens.example.org"]},
          {"bare host", ["lens.example.org"]},
          {"origin with a path", ["https://lens.example.org/live"]},
          {"one bad origin among good ones",
           ["https://lens.example.org", "http://lens.example.org"]},
          {"empty list", []},
          {"false", false}
        ] do
      @value value

      test label, %{tmp_dir: dir} do
        secrets_dir = write_secrets(dir)
        settings = %{valid_settings() | "check_origin" => @value}

        assert load_error(settings, secrets_dir) =~ "check_origin"
      end
    end
  end

  describe "unknown or missing keys" do
    test "an unknown top-level key stops startup", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)
      settings = Map.put(valid_settings(), "debug_mode", true)

      message = load_error(settings, secrets_dir)

      assert message =~ "debug_mode"
      assert message =~ ~r/unknown/i
    end

    test "an unknown key in the oidc section stops startup", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)
      settings = put_in(valid_settings(), ["oidc", "client_sekret"], "x")

      message = load_error(settings, secrets_dir)

      assert message =~ "client_sekret"
      assert message =~ ~r/unknown/i
    end

    for key <- ~w(public_host check_origin oidc) do
      @key key

      test "a missing #{key} stops startup", %{tmp_dir: dir} do
        secrets_dir = write_secrets(dir)
        settings = Map.delete(valid_settings(), @key)

        assert load_error(settings, secrets_dir) =~ @key
      end
    end
  end

  describe "startup wiring" do
    test "config/runtime.exs for prod with no config stops with MqttLens.Config.Error" do
      runtime_exs = Path.join(@project_root, "config/runtime.exs")

      assert_raise MqttLens.Config.Error, fn ->
        Config.Reader.read!(runtime_exs, env: :prod, target: :host)
      end
    end

    test "no signing or encryption salt is a literal in lib/ or in prod config" do
      files =
        Path.wildcard(Path.join(@project_root, "lib/**/*.{ex,exs,heex}")) ++
          Enum.map(~w(config/config.exs config/prod.exs config/runtime.exs), fn file ->
            Path.join(@project_root, file)
          end)

      literal_salt = ~r/(\w*salt\w*:\s*"|\w*salt\w*"?\s*=>\s*"|@\w*salt\w*\s+")/

      offenders =
        for file <- files,
            {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
            Regex.match?(literal_salt, line),
            do: "#{Path.relative_to(file, @project_root)}:#{number}: #{String.trim(line)}"

      assert offenders == [], "salts must come from secret files:\n" <> Enum.join(offenders, "\n")
    end
  end
end
