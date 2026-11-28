defmodule MqttLens.Authz.TopicExamples do
  @moduledoc """
  Fixed match examples for the MQTT topic matcher (ml-1qx.1).

  Each entry is `{filter, topic, expected, source}`. `source` is the MQTT 5.0
  section or the rule that the entry comes from. The unit tests run every entry
  against `MqttLens.Authz.Topic`. The property tests run every entry against
  `MqttLens.Authz.TopicReference`, so that the oracle is also checked.
  Every filter and every topic in this table is valid.
  """

  @examples [
    # MQTT 5.0, 4.7.1.2 Multi-level wildcard
    {"sport/tennis/player1/#", "sport/tennis/player1", true, "4.7.1.2"},
    {"sport/tennis/player1/#", "sport/tennis/player1/ranking", true, "4.7.1.2"},
    {"sport/tennis/player1/#", "sport/tennis/player1/score/wimbledon", true, "4.7.1.2"},
    {"sport/tennis/player1/#", "sport/tennis", false, "4.7.1.2"},
    {"sport/tennis/player1/#", "sport/tennis/player2", false, "4.7.1.2"},
    {"sport/#", "sport", true, "4.7.1.2"},
    {"sport/#", "sport/", true, "4.7.1.2"},
    {"sport/#", "sports", false, "4.7.1.2"},
    {"#", "sport", true, "4.7.1.2"},
    {"#", "sport/tennis/player1", true, "4.7.1.2"},

    # MQTT 5.0, 4.7.1.3 Single-level wildcard
    {"sport/tennis/+", "sport/tennis/player1", true, "4.7.1.3"},
    {"sport/tennis/+", "sport/tennis/player2", true, "4.7.1.3"},
    {"sport/tennis/+", "sport/tennis/player1/ranking", false, "4.7.1.3"},
    {"sport/+", "sport", false, "4.7.1.3"},
    {"sport/+", "sport/", true, "4.7.1.3"},
    {"+/+", "/finance", true, "4.7.1.3"},
    {"/+", "/finance", true, "4.7.1.3"},
    {"+", "/finance", false, "4.7.1.3"},
    {"+", "finance", true, "4.7.1.3"},
    {"sport/+/player1", "sport/tennis/player1", true, "4.7.1.3"},
    {"sport/+/player1", "sport/tennis/player2", false, "4.7.1.3"},
    {"+/tennis/#", "sport/tennis/player1/ranking", true, "4.7.1.3"},
    {"+/tennis/#", "sport/tennis", true, "4.7.1.3"},
    {"+/tennis/#", "sport/golf", false, "4.7.1.3"},

    # MQTT 5.0, 4.7.2 Topics beginning with $
    {"#", "$SYS/x", false, "4.7.2"},
    {"#", "$SYS", false, "4.7.2"},
    {"#", "$", false, "4.7.2"},
    {"+", "$SYS", false, "4.7.2"},
    {"+/#", "$SYS", false, "4.7.2"},
    {"+/x", "$SYS/x", false, "4.7.2"},
    {"+/monitor/Clients", "$SYS/monitor/Clients", false, "4.7.2"},
    {"$SYS/#", "$SYS/x", true, "4.7.2"},
    {"$SYS/#", "$SYS", true, "4.7.2"},
    {"$SYS/#", "$SYS/monitor/Clients", true, "4.7.2"},
    {"$SYS/+", "$SYS/x", true, "4.7.2"},
    {"$SYS/monitor/+", "$SYS/monitor/Clients", true, "4.7.2"},
    {"$SYS", "$SYS", true, "4.7.2"},
    {"$SYS/#", "SYS/x", false, "4.7.2"},
    {"a/+", "a/$b", true, "4.7.2 ($ only counts in the first level)"},
    {"#", "a/$SYS", true, "4.7.2 ($ only counts in the first level)"},
    {"+/$SYS", "a/$SYS", true, "4.7.2 ($ only counts in the first level)"},

    # Exact levels, case and length
    {"sport/tennis", "sport/tennis", true, "exact"},
    {"sport/tennis", "Sport/tennis", false, "exact (case-sensitive)"},
    {"sport/tennis", "sport/tennis/", false, "exact"},
    {"sport/tennis/", "sport/tennis", false, "exact"},
    {"sport", "sport/tennis", false, "exact"},
    {"sport/tennis", "sport", false, "exact"},
    {"sport/tennis", "sport/tennis ", false, "exact (spaces count)"},

    # Empty levels
    {"/", "/", true, "empty levels"},
    {"//", "//", true, "empty levels"},
    {"a//b", "a//b", true, "empty levels"},
    {"a/+/b", "a//b", true, "empty levels (+ matches an empty level)"},
    {"a/b", "a//b", false, "empty levels"},
    {"+/+", "/", true, "empty levels"},
    {"+", "/", false, "empty levels"},
    {"+/+/+", "//", true, "empty levels"},
    {"+/+", "//", false, "empty levels"},
    {"#", "/", true, "empty levels"},
    {"/#", "/", true, "empty levels"},
    {"/#", "/finance", true, "empty levels"},
    {"/#", "finance", false, "empty levels"},
    {"a/+", "a/", true, "empty levels"},
    {"a/#", "a/", true, "empty levels"},
    {"+/", "a/", true, "empty levels"},
    {"+/", "a", false, "empty levels"},

    # Multi-byte UTF-8 (compared byte by byte, MQTT 5.0 4.7.3: no normalization)
    {"€/+/ü", "€/x/ü", true, "multi-byte"},
    {"€/+/ü", "€/x/u", false, "multi-byte"},
    {"+", "日本語", true, "multi-byte"},
    {"日本/#", "日本", true, "multi-byte"},
    {"日本/#", "日本語", false, "multi-byte"},
    {"+/+", "é/€", true, "multi-byte"},
    {"é", "é", false, "multi-byte (no normalization, 4.7.3)"},
    {"é", "é", false, "multi-byte (no normalization, 4.7.3)"}
  ]

  @doc "All examples as `{filter, topic, expected, source}`."
  @spec all() :: [{String.t(), String.t(), boolean(), String.t()}]
  def all, do: @examples
end
