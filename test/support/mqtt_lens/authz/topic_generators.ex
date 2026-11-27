defmodule MqttLens.Authz.TopicGenerators do
  @moduledoc """
  StreamData generators for MQTT topics and filters (ml-1qx.1).

  The alphabet is small, so that random filters and topics often match. It has
  `$`, a space, multi-byte UTF-8 (2, 3 bytes) and empty levels. The level `$SYS`
  occurs often, so that the `$`-topic rule (MQTT 5.0, 4.7.2) gets many runs.

  Only `StreamData` functions are used (no macros).
  """

  alias StreamData, as: SD

  @chars ["a", "b", "$", " ", "é", "€", "日"]

  # Levels with a + that is not the whole level. No # in them.
  @bad_plus_levels ["a+", "+a", "++", "a+b", "é+", "+$", "+ "]

  # Levels with a # that is not the whole level. No + in them.
  @bad_hash_levels ["a#", "#a", "##", "a#b", "é#", "#$", "# "]

  # Single characters for any_string/0: separators, wildcards, U+0000 and bytes
  # that are not valid UTF-8 (a lone 0xFF, a cut 2-byte sequence, an overlong NUL).
  @any_chars ["a", "/", "+", "#", "$", "é", "€", " ", <<0>>, <<0xFF>>, <<0xC3>>, <<0xC0, 0x80>>]

  @doc "One topic level without wildcards. It can be empty."
  def level do
    chars = SD.map(SD.list_of(SD.member_of(@chars), min_length: 1, max_length: 3), &Enum.join/1)
    SD.frequency([{6, chars}, {2, SD.constant("")}, {2, SD.constant("$SYS")}])
  end

  @doc "A valid topic name as a list of levels."
  def topic_levels do
    SD.filter(SD.list_of(level(), min_length: 1, max_length: 5), &(&1 != [""]))
  end

  @doc "A valid topic name."
  def topic, do: SD.map(topic_levels(), &join/1)

  @doc "A valid topic filter as a list of levels."
  def filter_levels do
    body = SD.list_of(SD.frequency([{3, level()}, {1, SD.constant("+")}]), max_length: 5)

    {body, SD.boolean()}
    |> SD.tuple()
    |> SD.map(fn
      {levels, true} -> levels ++ ["#"]
      {levels, false} -> levels
    end)
    |> SD.filter(&(&1 != [] and &1 != [""]))
  end

  @doc "A valid topic filter."
  def filter, do: SD.map(filter_levels(), &join/1)

  @doc """
  A `{filter, topic}` pair. Both values are valid. Half of the pairs are
  independent. The other half has a filter made from the topic (some levels
  become `+`, some change, the tail can become `#`), so that many pairs match.
  """
  def filter_and_topic do
    SD.one_of([
      SD.tuple({filter(), topic()}),
      SD.bind(topic_levels(), fn levels ->
        SD.map(filter_levels_from(levels), &{join(&1), join(levels)})
      end)
    ])
  end

  @doc "A filter that is valid except for one + that is not a whole level."
  def misplaced_plus_filter do
    SD.map(with_bad_level(SD.member_of(@bad_plus_levels)), &join/1)
  end

  @doc """
  A filter that is valid except for one misplaced #: a # that is not a whole
  level, or a whole-level # that is not the last level.
  """
  def misplaced_hash_filter do
    hash_not_last =
      {plain_body(),
       SD.list_of(SD.one_of([level(), SD.constant("+")]), min_length: 1, max_length: 3)}
      |> SD.tuple()
      |> SD.map(fn {head, tail} -> join(head ++ ["#"] ++ tail) end)

    SD.one_of([SD.map(with_bad_level(SD.member_of(@bad_hash_levels)), &join/1), hash_not_last])
  end

  @doc """
  A short string from a small alphabet: `/`, `+`, `#`, `$`, U+0000, multi-byte
  UTF-8 and bytes that are not valid UTF-8. It can be empty. It can be valid or not.
  """
  def any_string do
    SD.map(SD.list_of(SD.member_of(@any_chars), max_length: 8), &Enum.join/1)
  end

  @doc "Any binary: random bytes or a string from any_string/0."
  def any_binary, do: SD.one_of([SD.binary(), any_string()])

  defp plain_body do
    SD.list_of(SD.frequency([{3, level()}, {1, SD.constant("+")}]), max_length: 3)
  end

  # Inserts one bad level into a valid body. The body can end with a whole-level #.
  defp with_bad_level(bad_level) do
    {plain_body(), bad_level, SD.integer(0..3), SD.boolean()}
    |> SD.tuple()
    |> SD.map(fn {body, bad, index, hash?} ->
      levels = List.insert_at(body, index, bad)
      if hash?, do: levels ++ ["#"], else: levels
    end)
  end

  defp filter_levels_from(topic_levels) do
    count = length(topic_levels)

    op =
      SD.frequency([{4, SD.constant(:keep)}, {2, SD.constant(:plus)}, {1, SD.constant(:change)}])

    tail = SD.member_of([:none, :hash, :extra])

    {SD.list_of(op, length: count), SD.integer(0..count), tail}
    |> SD.tuple()
    |> SD.map(fn {ops, cut, tail_kind} ->
      levels = Enum.zip_with(topic_levels, ops, &apply_op/2)

      case tail_kind do
        :none -> levels
        :hash -> Enum.take(levels, cut) ++ ["#"]
        :extra -> levels ++ ["a"]
      end
    end)
  end

  defp apply_op(level, :keep), do: level
  defp apply_op(_level, :plus), do: "+"
  defp apply_op(level, :change), do: level <> "x"

  defp join(levels), do: Enum.join(levels, "/")
end
