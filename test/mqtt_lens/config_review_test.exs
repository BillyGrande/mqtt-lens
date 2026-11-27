defmodule MqttLens.ConfigReviewTest do
  @moduledoc """
  Review round 1 of ml-1a7.2 (PR #19): fail-closed config gaps.

  Findings under test:

    * ml-1a7.2.1 - the OIDC issuer host is validated (no `;`, `,`, space,
      CR/LF, percent sign, userinfo, port out of 1..65535). A bad issuer
      stops startup with `MqttLens.Config.Error`.
    * ml-1a7.2.2 - `MqttLens.Config.read_settings!/1` is a strict TOML
      subset: duplicate keys and tables, a table that redefines a value, JSON
      objects and `null` raise `MqttLens.Config.Error` (never another
      exception). A full settings file is read.
    * ml-1a7.2.4 - prod `config/runtime.exs` puts the checked `check_origin`
      list into the `MqttLensWeb.Endpoint` config. No `check_origin: false`
      in lib/ or prod config (compensates the global Config.CSWH ignore).
    * ml-1a7.2.5 - the LiveView signing salt is not the session signing salt.
      The frozen config tests write only the three secret files
      (`secret_key_base`, `signing_salt`, `encryption_salt`), so the LiveView
      salt must come from these files (for example derived from
      `signing_salt`), not from a fourth required file.
    * ml-1a7.2.6 - `check_origin` ports are in 1..65535, and the list has an
      entry for `https://<public_host>`. The frozen test
      "accepts an exact https origin with a port" has only
      `https://lens.example.org:8443` for public_host `lens.example.org`, so
      an entry with the public host and any valid port counts.
    * ml-1a7.2.8 - `signing_salt` and `encryption_salt` are at least 8 bytes;
      the error message does not contain the value.

  The module is not async: the prod runtime tests set the
  `MQTT_LENS_CONFIG` and `MQTT_LENS_SECRETS_DIR` environment variables.
  """
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  @secret_key_base String.duplicate("k", 64) <> "-secret-key-base-value"
  @signing_salt "signing-salt-from-file"
  @encryption_salt "encryption-salt-from-file"

  @project_root Path.expand("../..", __DIR__)
  @runtime_exs Path.join(@project_root, "config/runtime.exs")

  @valid_toml """
  # mqtt-lens.toml
  public_host = "lens.example.org"
  check_origin = ["https://lens.example.org", "https://lens-alt.example.org"]

  [oidc]
  issuer = "https://id.example.org/realms/lens"
  """

  defp valid_settings do
    %{
      "public_host" => "lens.example.org",
      "check_origin" => ["https://lens.example.org"],
      "oidc" => %{"issuer" => "https://id.example.org/realms/lens"}
    }
  end

  defp write_secrets(dir, overrides \\ %{}) do
    secrets_dir = Path.join(dir, "secrets")
    File.mkdir_p!(secrets_dir)

    %{
      "secret_key_base" => @secret_key_base,
      "signing_salt" => @signing_salt,
      "encryption_salt" => @encryption_salt
    }
    |> Map.merge(overrides)
    |> Enum.each(fn {name, content} -> File.write!(Path.join(secrets_dir, name), content) end)

    secrets_dir
  end

  defp write_toml(dir, content, name \\ "mqtt-lens.toml") do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  defp load_error(settings, secrets_dir) do
    error =
      assert_raise MqttLens.Config.Error, fn ->
        MqttLens.Config.load!(settings, secrets_dir)
      end

    Exception.message(error)
  end

  defp read_error(path) do
    error =
      assert_raise MqttLens.Config.Error, fn ->
        MqttLens.Config.read_settings!(path)
      end

    Exception.message(error)
  end

  defp with_issuer(issuer), do: put_in(valid_settings(), ["oidc", "issuer"], issuer)

  # Reads config/runtime.exs for prod with the given settings file and
  # secrets directory. Restores the environment afterwards.
  defp read_prod_runtime(config_path, secrets_dir) do
    vars = ~w(MQTT_LENS_CONFIG MQTT_LENS_SECRETS_DIR PHX_SERVER)
    saved = Map.new(vars, &{&1, System.get_env(&1)})

    try do
      System.delete_env("PHX_SERVER")
      System.put_env("MQTT_LENS_CONFIG", config_path)
      System.put_env("MQTT_LENS_SECRETS_DIR", secrets_dir)
      Config.Reader.read!(@runtime_exs, env: :prod, target: :host)
    after
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end

  defp endpoint_config(runtime_config) do
    runtime_config |> Keyword.fetch!(:mqtt_lens) |> Keyword.fetch!(MqttLensWeb.Endpoint)
  end

  describe "ml-1a7.2.1: a bad OIDC issuer stops startup" do
    for {label, issuer} <- [
          {"semicolon in the host (CSP directive injection)", "https://kc.example;script-src *"},
          {"semicolon and path", "https://kc.example;script-src */realms/lens"},
          {"comma in the host", "https://kc.example,https://evil.example"},
          {"space in the host", "https://kc.example script-src"},
          {"CR/LF in the host (header injection)", "https://kc.example\r\nx: y"},
          {"LF in the host", "https://kc.example\nx"},
          {"CR in the host", "https://kc.example\rx"},
          {"percent sign in the host", "https://kc%2eexample/realms/lens"},
          {"userinfo with password", "https://u:p@kc.example/realms/lens"},
          {"userinfo without password", "https://u@kc.example/realms/lens"},
          {"port above 65535", "https://kc.example:99999/realms/lens"},
          {"port 65536", "https://kc.example:65536/realms/lens"},
          {"port 0", "https://kc.example:0/realms/lens"},
          {"not a string", 42}
        ] do
      @issuer issuer

      test label, %{tmp_dir: dir} do
        message = load_error(with_issuer(@issuer), write_secrets(dir))

        assert message =~ "issuer"
      end
    end

    test "the issuer origin is built from the validated host and port", %{tmp_dir: dir} do
      secrets_dir = write_secrets(dir)

      assert %{issuer_origin: "https://id.example.org"} =
               MqttLens.Config.load!(valid_settings(), secrets_dir)

      assert %{issuer_origin: "https://kc.example:8443"} =
               MqttLens.Config.load!(with_issuer("https://kc.example:8443/realms/x"), secrets_dir)

      assert %{issuer_origin: "https://kc.example"} =
               MqttLens.Config.load!(with_issuer("https://kc.example:443/realms/x"), secrets_dir)
    end

    test "prod runtime.exs with a bad issuer stops with MqttLens.Config.Error", %{tmp_dir: dir} do
      toml =
        String.replace(
          @valid_toml,
          ~s(issuer = "https://id.example.org/realms/lens"),
          ~s(issuer = "https://kc.example;script-src *")
        )

      config_path = write_toml(dir, toml)

      assert_raise MqttLens.Config.Error, fn ->
        read_prod_runtime(config_path, write_secrets(dir))
      end
    end
  end

  describe "ml-1a7.2.2: read_settings!/1 reads a strict TOML subset" do
    test "a full settings file with comments and blank lines is read", %{tmp_dir: dir} do
      path = write_toml(dir, @valid_toml)

      assert MqttLens.Config.read_settings!(path) == %{
               "public_host" => "lens.example.org",
               "check_origin" => ["https://lens.example.org", "https://lens-alt.example.org"],
               "oidc" => %{"issuer" => "https://id.example.org/realms/lens"}
             }
    end

    test "a duplicate top-level key stops startup", %{tmp_dir: dir} do
      path =
        write_toml(dir, """
        public_host = "a.example"
        public_host = "b.example"
        """)

      assert read_error(path) =~ "public_host"
    end

    test "a duplicate key in a table stops startup", %{tmp_dir: dir} do
      path =
        write_toml(dir, """
        [oidc]
        issuer = "https://a.example/realms/lens"
        issuer = "https://b.example/realms/lens"
        """)

      assert read_error(path) =~ "issuer"
    end

    test "a duplicate table stops startup", %{tmp_dir: dir} do
      path =
        write_toml(dir, """
        [oidc]
        issuer = "https://a.example/realms/lens"

        [oidc]
        issuer = "https://b.example/realms/lens"
        """)

      assert read_error(path) =~ "oidc"
    end

    test "a duplicate empty table stops startup", %{tmp_dir: dir} do
      path =
        write_toml(dir, """
        [oidc]
        [oidc]
        issuer = "https://a.example/realms/lens"
        """)

      assert read_error(path) =~ "oidc"
    end

    test "a table header for a key that holds a value stops startup (with keys)", %{tmp_dir: dir} do
      path =
        write_toml(dir, """
        oidc = "x"

        [oidc]
        issuer = "https://a.example/realms/lens"
        """)

      assert read_error(path) =~ "oidc"
    end

    test "a table header for a key that holds a value stops startup (no keys)", %{tmp_dir: dir} do
      path =
        write_toml(dir, """
        public_host = "a.example"

        [public_host]
        """)

      assert read_error(path) =~ "public_host"
    end

    for {label, line} <- [
          {"a JSON object value", ~s(oidc = {"issuer": "https://a.example/realms/lens"})},
          {"a JSON object in an array", ~s(check_origin = [{"origin": "https://a.example"}])},
          {"a null value", ~s(public_host = null)},
          {"a null in an array", ~s(check_origin = [null])}
        ] do
      @line line

      test "#{label} stops startup", %{tmp_dir: dir} do
        path = write_toml(dir, @line <> "\n")

        read_error(path)
      end
    end

    test "prod runtime.exs with a duplicate key stops with MqttLens.Config.Error",
         %{tmp_dir: dir} do
      config_path = write_toml(dir, @valid_toml <> ~s(issuer = "https://b.example/realms/x"\n))

      assert_raise MqttLens.Config.Error, fn ->
        read_prod_runtime(config_path, write_secrets(dir))
      end
    end
  end

  describe "ml-1a7.2.4: prod runtime.exs uses the checked config" do
    test "the Endpoint gets the exact check_origin list and the secrets", %{tmp_dir: dir} do
      config = read_prod_runtime(write_toml(dir, @valid_toml), write_secrets(dir))
      endpoint = endpoint_config(config)

      assert endpoint[:check_origin] == [
               "https://lens.example.org",
               "https://lens-alt.example.org"
             ]

      assert endpoint[:secret_key_base] == @secret_key_base
      assert endpoint[:session_signing_salt] == @signing_salt
      assert endpoint[:session_encryption_salt] == @encryption_salt
      assert endpoint[:url][:host] == "lens.example.org"
      assert config[:mqtt_lens][:oidc_origin] == "https://id.example.org"
    end

    test "no check_origin: false in lib/ or in prod config" do
      files =
        Path.wildcard(Path.join(@project_root, "lib/**/*.{ex,exs}")) ++
          Enum.map(~w(config/config.exs config/prod.exs config/runtime.exs), fn file ->
            Path.join(@project_root, file)
          end)

      offenders =
        for file <- files,
            {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
            Regex.match?(~r/check_origin\s*:\s*false|:check_origin\s*,\s*false/, line),
            do: "#{Path.relative_to(file, @project_root)}:#{number}: #{String.trim(line)}"

      assert offenders == [], "check_origin must not be off:\n" <> Enum.join(offenders, "\n")
    end
  end

  describe "ml-1a7.2.5: LiveView signing salt" do
    test "differs from the session signing and encryption salts", %{tmp_dir: dir} do
      endpoint =
        dir
        |> write_toml(@valid_toml)
        |> read_prod_runtime(write_secrets(dir))
        |> endpoint_config()

      lv_salt = endpoint[:live_view][:signing_salt]

      assert is_binary(lv_salt)
      assert byte_size(lv_salt) >= 8
      refute lv_salt == endpoint[:session_signing_salt]
      refute lv_salt == endpoint[:session_encryption_salt]
    end

    test "comes from the secret files, not from a literal", %{tmp_dir: dir} do
      config_path = write_toml(dir, @valid_toml)

      salt_for = fn signing_salt ->
        sub = Path.join(dir, signing_salt)
        File.mkdir_p!(sub)

        config_path
        |> read_prod_runtime(write_secrets(sub, %{"signing_salt" => signing_salt}))
        |> endpoint_config()
        |> get_in([:live_view, :signing_salt])
      end

      refute salt_for.("first-signing-salt") == salt_for.("second-signing-salt")
    end
  end

  describe "ml-1a7.2.6: check_origin port range and public host" do
    for {label, origins} <- [
          {"port above 65535", ["https://lens.example.org:99999"]},
          {"port 65536", ["https://lens.example.org:65536"]},
          {"port 0", ["https://lens.example.org:0"]},
          {"bad port among good origins", ["https://lens.example.org", "https://x.example:70000"]}
        ] do
      @origins origins

      test "#{label} stops startup", %{tmp_dir: dir} do
        settings = %{valid_settings() | "check_origin" => @origins}

        assert load_error(settings, write_secrets(dir)) =~ "check_origin"
      end
    end

    test "port 65535 is accepted", %{tmp_dir: dir} do
      settings = %{
        valid_settings()
        | "check_origin" => ["https://lens.example.org", "https://lens.example.org:65535"]
      }

      assert %{check_origin: ["https://lens.example.org", "https://lens.example.org:65535"]} =
               MqttLens.Config.load!(settings, write_secrets(dir))
    end

    test "a list with no https://<public_host> entry stops startup", %{tmp_dir: dir} do
      settings = %{valid_settings() | "check_origin" => ["https://other.example.org"]}

      message = load_error(settings, write_secrets(dir))

      assert message =~ "check_origin"
      assert message =~ "lens.example.org"
    end

    test "a sub-domain of public_host does not count as the public host", %{tmp_dir: dir} do
      settings = %{valid_settings() | "check_origin" => ["https://x.lens.example.org"]}

      assert load_error(settings, write_secrets(dir)) =~ "check_origin"
    end

    test "extra origins next to https://<public_host> are accepted", %{tmp_dir: dir} do
      origins = ["https://other.example.org", "https://lens.example.org"]
      settings = %{valid_settings() | "check_origin" => origins}

      assert %{check_origin: ^origins} = MqttLens.Config.load!(settings, write_secrets(dir))
    end
  end

  describe "ml-1a7.2.8: minimum salt length" do
    for name <- ~w(signing_salt encryption_salt) do
      @name name

      test "a #{name} shorter than 8 bytes stops startup, without the value in the message",
           %{tmp_dir: dir} do
        short = "Zq3x7Wv"
        message = load_error(valid_settings(), write_secrets(dir, %{@name => short}))

        assert message =~ @name
        refute message =~ short
      end

      test "a #{name} of 8 bytes is accepted", %{tmp_dir: dir} do
        secrets_dir = write_secrets(dir, %{@name => "Zq3x7Wv9"})

        assert %{} = MqttLens.Config.load!(valid_settings(), secrets_dir)
      end
    end
  end
end
