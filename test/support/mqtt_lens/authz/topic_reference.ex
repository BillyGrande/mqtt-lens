defmodule MqttLens.Authz.TopicReference do
  @moduledoc """
  Simple reference for the MQTT topic rules (test oracle for ml-1qx.1).

  It is slow and obvious on purpose: it splits a value into a list of levels and
  walks the lists recursively. The property tests compare
  `MqttLens.Authz.Topic` with this module.

  Rules (MQTT 5.0, sections 4.7.1, 4.7.2 and 4.7.3):

    * A level is the text between two `/` separators. Empty levels are allowed.
    * `+` matches exactly one level (also an empty level).
    * `#` matches the parent level and all levels below it (`a/#` matches `a`).
    * A topic whose first level starts with `$` never matches a filter whose
      first level is `+` or `#`.
    * Values are compared byte by byte. There is no Unicode normalization.
  """

  @max_bytes 65_535

  @doc "True if `filter` matches `topic`. Both values must be valid."
  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(filter, topic) do
    filter_levels = levels(filter)
    topic_levels = levels(topic)

    if dollar_topic?(topic_levels) and wildcard_first?(filter_levels) do
      false
    else
      match_levels(filter_levels, topic_levels)
    end
  end

  @doc "True if `value` is a valid MQTT topic name."
  @spec valid_topic?(binary()) :: boolean()
  def valid_topic?(value) do
    common_valid?(value) and not String.contains?(value, ["+", "#"])
  end

  @doc "True if `value` is a valid MQTT topic filter."
  @spec valid_filter?(binary()) :: boolean()
  def valid_filter?(value) do
    common_valid?(value) and valid_filter_levels?(levels(value))
  end

  @doc ~S|Splits a value into its levels. `"a//b"` gives `["a", "", "b"]`.|
  @spec levels(binary()) :: [binary()]
  def levels(value), do: :binary.split(value, "/", [:global])

  defp common_valid?(value) do
    byte_size(value) in 1..@max_bytes and String.valid?(value) and
      not String.contains?(value, <<0>>)
  end

  defp valid_filter_levels?([]), do: true
  defp valid_filter_levels?(["#"]), do: true
  defp valid_filter_levels?(["#" | _rest]), do: false
  defp valid_filter_levels?(["+" | rest]), do: valid_filter_levels?(rest)

  defp valid_filter_levels?([level | rest]) do
    not String.contains?(level, ["+", "#"]) and valid_filter_levels?(rest)
  end

  defp match_levels(["#"], _topic_levels), do: true

  defp match_levels(["+" | filter_rest], [_level | topic_rest]),
    do: match_levels(filter_rest, topic_rest)

  defp match_levels([level | filter_rest], [level | topic_rest]),
    do: match_levels(filter_rest, topic_rest)

  defp match_levels([], []), do: true
  defp match_levels(_filter_levels, _topic_levels), do: false

  defp dollar_topic?(["$" <> _rest | _levels]), do: true
  defp dollar_topic?(_levels), do: false

  defp wildcard_first?([first | _levels]), do: first in ["+", "#"]
end
