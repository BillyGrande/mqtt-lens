defmodule MqttLens.Authz.Topic do
  @moduledoc """
  Pure MQTT topic name and topic filter checks.

  `validate_topic/1` and `validate_filter/1` check a value and never raise.
  `matches?/2` is only for values that passed validation.
  """

  @max_bytes 65_535

  @type reason ::
          :not_a_binary
          | :empty
          | :too_long
          | :invalid_utf8
          | :null_char
          | :wildcard_in_topic
          | :misplaced_plus
          | :misplaced_hash

  @doc """
  Checks a topic name. Returns `:ok` or `{:error, reason}`.

  A topic name has 1 to 65535 bytes, is valid UTF-8, and has no U+0000, `+` or `#`.
  """
  @spec validate_topic(term()) :: :ok | {:error, reason()}
  def validate_topic(topic) do
    with :ok <- validate_common(topic) do
      if String.contains?(topic, ["+", "#"]), do: {:error, :wildcard_in_topic}, else: :ok
    end
  end

  @doc """
  Checks a topic filter. Returns `:ok` or `{:error, reason}`.

  `+` must be a whole level. `#` must be a whole level and the last level.
  """
  @spec validate_filter(term()) :: :ok | {:error, reason()}
  def validate_filter(filter) do
    with :ok <- validate_common(filter) do
      filter |> String.split("/") |> check_levels()
    end
  end

  @doc """
  Returns `true` if the topic name matches the topic filter.

  Use it only for values that passed validation. A topic whose first level
  starts with `$` does not match a filter whose first level is `+` or `#`.
  """
  @spec matches?(binary(), binary()) :: boolean()
  def matches?(filter, topic) when is_binary(filter) and is_binary(topic) do
    filter_levels = String.split(filter, "/")
    [first | _] = topic_levels = String.split(topic, "/")

    if String.starts_with?(first, "$") and hd(filter_levels) in ["+", "#"] do
      false
    else
      match_levels(filter_levels, topic_levels)
    end
  end

  defp validate_common(value) when not is_binary(value), do: {:error, :not_a_binary}
  defp validate_common(""), do: {:error, :empty}
  defp validate_common(value) when byte_size(value) > @max_bytes, do: {:error, :too_long}

  defp validate_common(value) do
    cond do
      not String.valid?(value) -> {:error, :invalid_utf8}
      String.contains?(value, <<0>>) -> {:error, :null_char}
      true -> :ok
    end
  end

  defp check_levels([]), do: :ok
  defp check_levels(["#"]), do: :ok
  defp check_levels(["#" | _]), do: {:error, :misplaced_hash}
  defp check_levels(["+" | rest]), do: check_levels(rest)

  defp check_levels([level | rest]) do
    cond do
      String.contains?(level, "#") -> {:error, :misplaced_hash}
      String.contains?(level, "+") -> {:error, :misplaced_plus}
      true -> check_levels(rest)
    end
  end

  defp match_levels(["#"], _topic), do: true
  defp match_levels([], []), do: true
  defp match_levels(["+" | f], [_ | t]), do: match_levels(f, t)
  defp match_levels([level | f], [level | t]), do: match_levels(f, t)
  defp match_levels(_filter, _topic), do: false
end
