defmodule MqttLens.Authz.TopicPropertyTest do
  @moduledoc """
  Property tests for `MqttLens.Authz.Topic` (ml-1qx.1, criteria 2 and 3).

  Specs: features/authorization.md#model, architecture/testing.md (Property).

  `matches?/2` is compared with the simple reference matcher in
  `MqttLens.Authz.TopicReference` (level lists, recursive). The generators are
  in `MqttLens.Authz.TopicGenerators`. Each property has at least 1000 runs.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias MqttLens.Authz.Topic
  alias MqttLens.Authz.TopicExamples
  alias MqttLens.Authz.TopicGenerators, as: Gen
  alias MqttLens.Authz.TopicReference, as: Reference

  @runs 1_000

  @reasons [
    :not_a_binary,
    :empty,
    :too_long,
    :invalid_utf8,
    :null_char,
    :wildcard_in_topic,
    :misplaced_plus,
    :misplaced_hash
  ]

  describe "the oracle" do
    test "the reference matcher agrees with every fixed example" do
      for {filter, topic, expected, source} <- TopicExamples.all() do
        assert Reference.valid_filter?(filter), "filter #{inspect(filter)} (#{source})"
        assert Reference.valid_topic?(topic), "topic #{inspect(topic)} (#{source})"

        assert Reference.matches?(filter, topic) == expected,
               "#{inspect(filter)} vs #{inspect(topic)} (#{source})"
      end
    end

    test "the pair generator gives matches, non-matches and $-topics with a wildcard first level" do
      pairs = Enum.take(Gen.filter_and_topic(), 2_000)
      matching = Enum.count(pairs, fn {filter, topic} -> Reference.matches?(filter, topic) end)

      dollar_vs_wildcard =
        Enum.count(pairs, fn {filter, topic} ->
          String.starts_with?(topic, "$") and String.starts_with?(filter, ["+", "#"])
        end)

      assert matching >= 200, "only #{matching} of 2000 pairs match"
      assert matching <= 1_800, "#{matching} of 2000 pairs match"

      assert dollar_vs_wildcard >= 20,
             "only #{dollar_vs_wildcard} $-topics with a wildcard filter"
    end

    test "the generators give values that the reference accepts or rejects as planned" do
      assert Enum.all?(Enum.take(Gen.topic(), 500), &Reference.valid_topic?/1)
      assert Enum.all?(Enum.take(Gen.filter(), 500), &Reference.valid_filter?/1)
      refute Enum.any?(Enum.take(Gen.misplaced_plus_filter(), 500), &Reference.valid_filter?/1)
      refute Enum.any?(Enum.take(Gen.misplaced_hash_filter(), 500), &Reference.valid_filter?/1)
    end
  end

  describe "matches?/2" do
    property "agrees with the reference matcher on valid filters and topics" do
      check all({filter, topic} <- Gen.filter_and_topic(), max_runs: @runs) do
        assert Topic.validate_filter(filter) == :ok
        assert Topic.validate_topic(topic) == :ok
        assert Topic.matches?(filter, topic) == Reference.matches?(filter, topic)
      end
    end

    property "a topic name used as a filter matches itself" do
      check all(topic <- Gen.topic(), max_runs: @runs) do
        assert Topic.matches?(topic, topic)
      end
    end

    property "# matches a topic if and only if the topic does not start with $" do
      check all(topic <- Gen.topic(), max_runs: @runs) do
        assert Topic.matches?("#", topic) == not String.starts_with?(topic, "$")
      end
    end
  end

  describe "validation" do
    property "validate_topic/1 accepts every generated topic" do
      check all(topic <- Gen.topic(), max_runs: @runs) do
        assert Topic.validate_topic(topic) == :ok
      end
    end

    property "validate_filter/1 accepts every generated valid filter" do
      check all(filter <- Gen.filter(), max_runs: @runs) do
        assert Topic.validate_filter(filter) == :ok
      end
    end

    property "validate_filter/1 rejects every filter with a misplaced +" do
      check all(filter <- Gen.misplaced_plus_filter(), max_runs: @runs) do
        assert Topic.validate_filter(filter) == {:error, :misplaced_plus}
      end
    end

    property "validate_filter/1 rejects every filter with a misplaced #" do
      check all(filter <- Gen.misplaced_hash_filter(), max_runs: @runs) do
        assert Topic.validate_filter(filter) == {:error, :misplaced_hash}
      end
    end

    property "validate_topic/1 rejects a generated filter with a wildcard" do
      check all(filter <- Gen.filter(), String.contains?(filter, ["+", "#"]), max_runs: @runs) do
        assert Topic.validate_topic(filter) == {:error, :wildcard_in_topic}
      end
    end

    property "validate_topic/1 and validate_filter/1 agree with the reference on short strings" do
      check all(value <- Gen.any_string(), max_runs: @runs) do
        topic_ok? = Topic.validate_topic(value) == :ok
        filter_ok? = Topic.validate_filter(value) == :ok

        assert topic_ok? == Reference.valid_topic?(value)
        assert filter_ok? == Reference.valid_filter?(value)
      end
    end
  end

  describe "no function raises" do
    property "on any binary, validation gives :ok or a reason from the closed list" do
      check all(value <- Gen.any_binary(), max_runs: @runs) do
        assert valid_result?(Topic.validate_topic(value))
        assert valid_result?(Topic.validate_filter(value))
      end
    end

    property "on any binaries, matches?/2 gives a boolean" do
      check all(filter <- Gen.any_binary(), topic <- Gen.any_binary(), max_runs: @runs) do
        assert is_boolean(Topic.matches?(filter, topic))
      end
    end

    property "on any term, validation gives :ok or {:error, :not_a_binary} for non-binaries" do
      check all(value <- Gen.non_binary_term(), max_runs: @runs) do
        topic_result = Topic.validate_topic(value)
        filter_result = Topic.validate_filter(value)

        assert valid_result?(topic_result)
        assert valid_result?(filter_result)

        unless is_binary(value) do
          assert topic_result == {:error, :not_a_binary}
          assert filter_result == {:error, :not_a_binary}
        end
      end
    end
  end

  defp valid_result?(:ok), do: true
  defp valid_result?({:error, reason}), do: reason in @reasons
  defp valid_result?(_other), do: false
end
