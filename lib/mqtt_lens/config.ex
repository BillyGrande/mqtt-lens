defmodule MqttLens.Config do
  @moduledoc """
  Fail-closed startup configuration.

  `load!/2` checks the non-secret settings (parsed `mqtt-lens.toml`, string keys)
  and reads the secrets from files. On any problem it raises
  `MqttLens.Config.Error`, so the application does not start.

  Spec: architecture/deployment.md#configuration-and-secrets.
  """

  alias MqttLens.Config.Files

  defmodule Error do
    @moduledoc "Raised when the startup configuration is not valid."
    defexception [:message]

    @impl true
    def exception(message) when is_binary(message), do: %__MODULE__{message: message}
  end

  @top_keys ~w(public_host check_origin oidc)
  @oidc_keys ~w(issuer)
  @secret_names ~w(secret_key_base signing_salt encryption_salt)
  @min_secret_key_base_bytes 64
  @min_salt_bytes 8

  @host_re ~r/\A[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z/
  @origin_re ~r|\Ahttps://([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::(\d{1,5}))?\z|
  @issuer_re ~r|\Ahttps://([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::(\d{1,5}))?(?:/[^\s\x00-\x1f\x7f]*)?\z|

  @doc """
  Validate `settings` and read the secrets from `secrets_dir`.

  Returns a map with `:secret_key_base`, `:signing_salt`, `:encryption_salt`,
  `:check_origin`, `:public_host`, `:issuer` and `:issuer_origin`.
  """
  @spec load!(map(), Path.t()) :: map()
  def load!(settings, secrets_dir) when is_map(settings) do
    {secrets, secret_errors} = read_secrets(secrets_dir)

    errors =
      unknown_key_errors(settings, @top_keys, "") ++
        public_host_errors(settings) ++
        check_origin_errors(settings) ++
        issuer_errors(settings) ++
        secret_errors

    case errors do
      [] ->
        issuer = settings["oidc"]["issuer"]

        Map.merge(secrets, %{
          live_view_salt: live_view_salt(secrets.signing_salt),
          check_origin: settings["check_origin"],
          public_host: settings["public_host"],
          issuer: issuer,
          issuer_origin: origin(issuer)
        })

      errors ->
        raise Error, "invalid configuration:\n" <> Enum.map_join(errors, "\n", &("  - " <> &1))
    end
  end

  def load!(_settings, _secrets_dir), do: raise(Error, "settings must be a table")

  # A separate salt for LiveView, derived from the signing salt, so it is not
  # the same as the session salt and no fourth secret file is needed.
  defp live_view_salt(signing_salt) do
    :hmac
    |> :crypto.mac(:sha256, signing_salt, "mqtt-lens live_view signing salt")
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Read a settings file. Only a small TOML subset is supported: `[table]`
  headers and `key = value` lines where the value is a string, boolean,
  number or array of these in JSON syntax. Duplicate keys or tables, a table
  header over a value, and other value types raise `Error`. A missing or unreadable file raises.
  """
  # The path comes from operator config (an env var), not from a request.
  @spec read_settings!(Path.t()) :: map()
  def read_settings!(path) do
    case Files.read(path) do
      {:ok, content} ->
        parse_settings!(content, path)

      {:error, reason} ->
        raise Error, "config file #{path} cannot be read: #{:file.format_error(reason)}"
    end
  end

  defp parse_settings!(content, path) do
    {settings, _section} =
      content
      |> String.split(["\r\n", "\n"])
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, nil}, fn {line, number}, {settings, section} ->
        parse_line(String.trim(line), settings, section, "#{path}:#{number}")
      end)

    settings
  end

  defp parse_line("", settings, section, _where), do: {settings, section}
  defp parse_line("#" <> _comment, settings, section, _where), do: {settings, section}

  defp parse_line("[" <> _ = line, settings, _section, where) do
    case Regex.run(~r/\A\[([A-Za-z0-9_-]+)\]\z/, line) do
      [_, name] ->
        if Map.has_key?(settings, name),
          do: raise(Error, "#{where}: #{name} is defined twice"),
          else: {Map.put(settings, name, %{}), name}

      _ ->
        raise Error, "#{where}: unsupported table header"
    end
  end

  defp parse_line(line, settings, section, where) do
    with [_, key, value_text] <- Regex.run(~r/\A([A-Za-z0-9_-]+)\s*=\s*(.+)\z/, line),
         {:ok, value} <- JSON.decode(value_text),
         true <- simple_value?(value) do
      {put_value(settings, section, key, value, where), section}
    else
      _ -> raise Error, "#{where}: unsupported or invalid syntax"
    end
  end

  defp simple_value?(value) when is_binary(value) or is_boolean(value) or is_number(value),
    do: true

  defp simple_value?(list) when is_list(list),
    do: Enum.all?(list, &(is_binary(&1) or is_boolean(&1) or is_number(&1)))

  defp simple_value?(_), do: false

  defp put_value(settings, nil, key, value, where) do
    if Map.has_key?(settings, key),
      do: raise(Error, "#{where}: #{key} is defined twice"),
      else: Map.put(settings, key, value)
  end

  defp put_value(settings, section, key, value, where) do
    if Map.has_key?(settings[section], key),
      do: raise(Error, "#{where}: #{section}.#{key} is defined twice"),
      else: put_in(settings, [section, key], value)
  end

  defp unknown_key_errors(map, allowed, prefix) do
    for key <- Map.keys(map), key not in allowed do
      "unknown setting #{prefix}#{inspect_key(key)}"
    end
  end

  defp inspect_key(key) when is_binary(key), do: key
  defp inspect_key(key), do: inspect(key)

  defp public_host_errors(%{"public_host" => host}) do
    if is_binary(host) and Regex.match?(@host_re, host),
      do: [],
      else: ["public_host must be a host name"]
  end

  defp public_host_errors(_), do: ["public_host is missing"]

  defp check_origin_errors(%{"check_origin" => [_ | _] = origins} = settings) do
    bad =
      for origin <- origins, not valid_origin?(origin) do
        "check_origin entry #{inspect(origin)} is not an exact https:// origin " <>
          "(scheme, host, optional port 1-65535; no wildcard, no path)"
      end

    bad ++ public_host_origin_errors(settings, origins)
  end

  defp check_origin_errors(%{"check_origin" => _}),
    do: ["check_origin must be a non-empty list of exact https:// origins"]

  defp check_origin_errors(_), do: ["check_origin is missing"]

  defp valid_origin?(origin) when is_binary(origin), do: valid_port_match?(@origin_re, origin)
  defp valid_origin?(_), do: false

  defp valid_port_match?(re, string) do
    case Regex.run(re, string) do
      nil -> false
      [_, _host] -> true
      [_, _host, port] -> port_ok?(port)
    end
  end

  defp port_ok?(port) do
    String.to_integer(port) in 1..65_535
  end

  defp public_host_origin_errors(%{"public_host" => host}, origins) when is_binary(host) do
    present? =
      Enum.any?(origins, fn origin ->
        is_binary(origin) and match?([_, ^host | _], Regex.run(@origin_re, origin))
      end)

    if present?,
      do: [],
      else: ["check_origin has no entry for https://#{host} (the public_host)"]
  end

  defp public_host_origin_errors(_, _), do: []

  defp issuer_errors(%{"oidc" => %{} = oidc}) do
    unknown_key_errors(oidc, @oidc_keys, "oidc.") ++
      case oidc do
        %{"issuer" => issuer} ->
          if is_binary(issuer) and valid_port_match?(@issuer_re, issuer),
            do: [],
            else: [
              "oidc.issuer must be an https:// URL with a plain host, " <>
                "an optional port 1-65535, and no user info or control characters"
            ]

        _ ->
          ["oidc.issuer is missing"]
      end
  end

  defp issuer_errors(%{"oidc" => _}), do: ["oidc must be a table with an issuer"]
  defp issuer_errors(_), do: ["oidc is missing (oidc.issuer is required)"]

  defp origin(issuer) do
    case Regex.run(@issuer_re, issuer) do
      [_, host] -> "https://" <> host
      [_, host, "443"] -> "https://" <> host
      [_, host, port] -> "https://#{host}:#{String.to_integer(port)}"
    end
  end

  defp read_secrets(dir) do
    if Files.dir?(dir) do
      results = Map.new(@secret_names, &{&1, read_secret(dir, &1)})

      secrets =
        for {name, {:ok, value}} <- results, into: %{}, do: {String.to_existing_atom(name), value}

      errors = for {_name, {:error, message}} <- results, do: message
      {secrets, errors}
    else
      {%{}, ["secrets directory #{dir} does not exist"]}
    end
  end

  # `dir` is operator config and `name` is one of a fixed list.
  defp read_secret(dir, name) do
    case Files.read_in(dir, name) do
      {:ok, content} -> check_secret(name, String.trim(content))
      {:error, _} -> {:error, "secret #{name} is missing or unreadable"}
    end
  end

  defp check_secret(name, ""), do: {:error, "secret #{name} is empty"}

  defp check_secret("secret_key_base", value) when byte_size(value) < @min_secret_key_base_bytes,
    do: {:error, "secret secret_key_base must be at least #{@min_secret_key_base_bytes} bytes"}

  defp check_secret(name, value)
       when name in ["signing_salt", "encryption_salt"] and byte_size(value) < @min_salt_bytes,
       do: {:error, "secret #{name} must be at least #{@min_salt_bytes} bytes"}

  defp check_secret(_name, value), do: {:ok, value}
end
