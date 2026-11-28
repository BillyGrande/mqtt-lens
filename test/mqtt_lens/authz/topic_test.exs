defmodule MqttLens.Authz.TopicTest do
  @moduledoc """
  Unit tests for MQTT topic and filter validation and matching (ml-1qx.1,
  criteria 1 and 3).

  Specs: features/authorization.md#model, architecture/testing.md (Unit).
  MQTT 5.0 sections 4.7.1.2, 4.7.1.3, 4.7.2 and 4.7.3.

  Contract under test (`MqttLens.Authz.Topic`):

    * `validate_topic(term) :: :ok | {:error, reason}`. A topic name is a binary,
      valid UTF-8, 1..65535 bytes, no U+0000, no `+` and no `#`.
    * `validate_filter(term) :: :ok | {:error, reason}`. A filter is a binary,
      valid UTF-8, 1..65535 bytes, no U+0000. `+` is a whole level. `#` is a whole
      level and the last level. Empty levels are allowed.
    * `matches?(filter, topic) :: boolean`. It never raises on binaries.
    * `reason` is one atom from this closed list:

        * `:not_a_binary`      the value is not a binary
        * `:empty`             0 bytes
        * `:too_long`          more than 65535 bytes
        * `:invalid_utf8`      the bytes are not valid UTF-8
        * `:null_char`         the value contains U+0000
        * `:wildcard_in_topic` a topic name contains `+` or `#`
        * `:misplaced_plus`    a filter has a `+` that is not a whole level
        * `:misplaced_hash`    a filter has a `#` that is not a whole level, or not the last level

  Each test input breaks one rule only.
  """
  use ExUnit.Case, async: true

  alias MqttLens.Authz.Topic
  alias MqttLens.Authz.TopicExamples

  @max 65_535

  @invalid_utf8 [
    {"a lone 0xFF byte", <<0xFF>>},
    {"a cut 2-byte sequence", <<0xC3>>},
    {"a cut 3-byte sequence after a valid level", "sport/" <> <<0xE2, 0x82>>},
    {"an overlong encoding of U+0000", <<0xC0, 0x80>>},
    {"a UTF-16 surrogate (U+D800)", <<0xED, 0xA0, 0x80>>},
    {"a code point above U+10FFFF", <<0xF4, 0x90, 0x80, 0x80>>},
    {"a continuation byte without a lead byte", "a" <> <<0x80>> <> "b"}
  ]

  defp non_binaries do
    [
      nil,
      42,
      1.5,
      :sport,
      true,
      ~c"sport/tennis",
      ["sport", "tennis"],
      %{topic: "sport"},
      {"sport"},
      <<1::3>>,
      <<"sport", 1::1>>,
      self(),
      make_ref(),
      fn -> "sport" end
    ]
  end

  describe "validate_topic/1 accepts valid topic names" do
    for topic <- [
          "sport",
          "sport/tennis/player1",
          "/",
          "//",
          "/finance",
          "finance/",
          "a//b",
          "$SYS",
          "$SYS/monitor/Clients",
          "a/$b",
          "sport tennis",
          "€/ü/日本語",
          "é"
        ] do
      test "#{inspect(topic)}" do
        assert Topic.validate_topic(unquote(topic)) == :ok
      end
    end

    test "exactly 65535 bytes" do
      assert Topic.validate_topic(String.duplicate("a", @max)) == :ok
    end

    test "exactly 65535 bytes of 3-byte characters" do
      topic = String.duplicate("€", div(@max, 3))
      assert byte_size(topic) == @max
      assert Topic.validate_topic(topic) == :ok
    end
  end

  describe "validate_topic/1 rejects" do
    test "an empty binary with :empty" do
      assert Topic.validate_topic("") == {:error, :empty}
    end

    test "65536 bytes with :too_long" do
      assert Topic.validate_topic(String.duplicate("a", @max + 1)) == {:error, :too_long}
    end

    test "65536 bytes of multi-byte characters with :too_long (the limit is in bytes)" do
      topic = String.duplicate("€", div(@max, 3)) <> "a"
      assert byte_size(topic) == @max + 1
      assert Topic.validate_topic(topic) == {:error, :too_long}
    end

    test "fewer than 65536 characters but more than 65535 bytes with :too_long" do
      topic = String.duplicate("é", 40_000)
      assert String.length(topic) == 40_000
      assert Topic.validate_topic(topic) == {:error, :too_long}
    end

    for {name, value} <- @invalid_utf8 do
      test "#{name} with :invalid_utf8" do
        assert Topic.validate_topic(unquote(value)) == {:error, :invalid_utf8}
      end
    end

    for topic <- ["\0", "a\0b", "sport/\0", "\0/tennis"] do
      test "U+0000 in #{inspect(topic)} with :null_char" do
        assert Topic.validate_topic(unquote(topic)) == {:error, :null_char}
      end
    end

    for topic <- [
          "+",
          "#",
          "sport/+",
          "sport/#",
          "+/tennis",
          "sport+",
          "sport/tennis#",
          "a/+/b",
          "$SYS/#"
        ] do
      test "the wildcard in #{inspect(topic)} with :wildcard_in_topic" do
        assert Topic.validate_topic(unquote(topic)) == {:error, :wildcard_in_topic}
      end
    end

    test "every non-binary with :not_a_binary, without a raise" do
      for value <- non_binaries() do
        assert Topic.validate_topic(value) == {:error, :not_a_binary}, "value: #{inspect(value)}"
      end
    end
  end

  describe "validate_filter/1 accepts valid filters" do
    for filter <- [
          # MQTT 5.0, 4.7.1.2 and 4.7.1.3
          "sport/tennis/player1/#",
          "sport/#",
          "#",
          "sport/tennis/+",
          "+",
          "+/+",
          "/+",
          "+/tennis/#",
          "sport/+/player1",
          # MQTT 5.0, 4.7.2
          "$SYS/#",
          "$SYS/monitor/+",
          # Empty levels
          "/",
          "//",
          "a//b",
          "+/",
          "/#",
          "+//#",
          # Plain names and multi-byte UTF-8
          "sport",
          "sport/tennis",
          "€/+/ü",
          "日本/#"
        ] do
      test "#{inspect(filter)}" do
        assert Topic.validate_filter(unquote(filter)) == :ok
      end
    end

    test "exactly 65535 bytes that end with /#" do
      filter = String.duplicate("a", @max - 2) <> "/#"
      assert byte_size(filter) == @max
      assert Topic.validate_filter(filter) == :ok
    end
  end

  describe "validate_filter/1 rejects" do
    test "an empty binary with :empty" do
      assert Topic.validate_filter("") == {:error, :empty}
    end

    test "65536 bytes with :too_long" do
      assert Topic.validate_filter(String.duplicate("a", @max + 1)) == {:error, :too_long}
    end

    test "65536 bytes that end with /# with :too_long" do
      filter = String.duplicate("a", @max - 1) <> "/#"
      assert byte_size(filter) == @max + 1
      assert Topic.validate_filter(filter) == {:error, :too_long}
    end

    test "65536 bytes of multi-byte characters with :too_long" do
      filter = String.duplicate("€", div(@max, 3)) <> "a"
      assert Topic.validate_filter(filter) == {:error, :too_long}
    end

    for {name, value} <- @invalid_utf8 do
      test "#{name} with :invalid_utf8" do
        assert Topic.validate_filter(unquote(value)) == {:error, :invalid_utf8}
      end
    end

    test "invalid UTF-8 next to a valid wildcard with :invalid_utf8" do
      assert Topic.validate_filter(<<0xFF>> <> "/#") == {:error, :invalid_utf8}
    end

    for filter <- ["\0", "a\0b", "sport/\0", "\0/#", "+/\0"] do
      test "U+0000 in #{inspect(filter)} with :null_char" do
        assert Topic.validate_filter(unquote(filter)) == {:error, :null_char}
      end
    end

    # MQTT 5.0, 4.7.1.3: "sport+" is not valid.
    for filter <- [
          "sport+",
          "sport/+tennis",
          "+a",
          "a+/b",
          "++",
          "sport/te+nnis",
          "+/a+",
          "€+",
          "+$SYS/#"
        ] do
      test "the + in #{inspect(filter)} with :misplaced_plus" do
        assert Topic.validate_filter(unquote(filter)) == {:error, :misplaced_plus}
      end
    end

    # MQTT 5.0, 4.7.1.2: "sport/tennis#" and "sport/tennis/#/ranking" are not valid.
    for filter <- [
          "sport/tennis#",
          "sport/tennis/#/ranking",
          "#/",
          "#/a",
          "a/#/",
          "a#",
          "#a",
          "##",
          "sport/#/#",
          "+/#/+",
          "€#"
        ] do
      test "the # in #{inspect(filter)} with :misplaced_hash" do
        assert Topic.validate_filter(unquote(filter)) == {:error, :misplaced_hash}
      end
    end

    test "every non-binary with :not_a_binary, without a raise" do
      for value <- non_binaries() do
        assert Topic.validate_filter(value) == {:error, :not_a_binary}, "value: #{inspect(value)}"
      end
    end
  end

  describe "matches?/2 with the fixed examples" do
    for {filter, topic, expected, source} <- TopicExamples.all() do
      verb = if expected, do: "matches", else: "does not match"

      test "#{inspect(filter)} #{verb} #{inspect(topic)} (#{source})" do
        assert Topic.validate_filter(unquote(filter)) == :ok
        assert Topic.validate_topic(unquote(topic)) == :ok
        assert Topic.matches?(unquote(filter), unquote(topic)) == unquote(expected)
      end
    end
  end

  describe "matches?/2 is total on binaries" do
    test "it returns a boolean for values that did not pass validation" do
      values = [
        "",
        "\0",
        <<0xFF>>,
        <<0xC3>>,
        "a+",
        "#/a",
        "+",
        "#",
        "$SYS",
        "/",
        String.duplicate("a", @max + 1)
      ]

      for filter <- values, topic <- values do
        assert is_boolean(Topic.matches?(filter, topic)),
               "matches?(#{inspect(filter, limit: 8)}, #{inspect(topic, limit: 8)})"
      end
    end
  end
end

defmodule MqttLens.Authz.TopicAtomTest do
  @moduledoc """
  The reason atoms come from a closed list in the module. Input never makes a
  new atom (ml-1qx.1). This module is not async, so that no other test adds
  atoms during the count.
  """
  use ExUnit.Case, async: false

  alias MqttLens.Authz.Topic

  test "validation and matching of new values do not add atoms" do
    # Load the module and its reason atoms before the count.
    _ = Topic.validate_topic("warm/up")
    _ = Topic.validate_filter("warm/+/#")
    _ = Topic.matches?("warm/#", "warm/up")
    # Load the String.Chars code for the interpolation below.
    _ = "warm-#{1}-#{System.unique_integer([:positive])}"

    before = :erlang.system_info(:atom_count)

    for n <- 1..2_000 do
      value = "atom-probe-#{n}-#{System.unique_integer([:positive])}"
      _ = Topic.validate_topic(value)
      _ = Topic.validate_topic(value <> "+")
      _ = Topic.validate_filter(value <> "/#")
      _ = Topic.validate_filter(value <> "#")
      _ = Topic.validate_filter(value <> "+")
      _ = Topic.matches?(value <> "/+", value <> "/x")
    end

    assert :erlang.system_info(:atom_count) == before
  end
end
