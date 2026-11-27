defmodule MqttLens.UnsafeGrepScriptTest do
  use ExUnit.Case, async: true

  @script Path.expand("../../scripts/ci/unsafe-grep.sh", __DIR__)

  @forms [
    "x |> raw",
    "raw(x)",
    "Enum.map(xs, &raw/1)",
    "Enum.map(xs, &Phoenix.HTML.raw/1)",
    "x |> Phoenix.HTML.raw",
    "Phoenix.HTML.raw(x)",
    "apply(Phoenix.HTML, :raw, [x])",
    "{:safe, x}",
    "String.to_atom(x)",
    "x |> String.to_atom",
    "Enum.map(xs, &String.to_atom/1)",
    "apply(String, :to_atom, [x])",
    "Enum.map(xs, &:erlang.binary_to_atom/1)",
    "Enum.map(xs, &:erlang.list_to_atom/1)",
    ":erlang.binary_to_atom(x, :utf8)",
    "x |> :erlang.list_to_atom",
    "List.to_atom(x)",
    "Jason.decode!(x, keys: :atoms)"
  ]

  setup do
    dir = Path.join(System.tmp_dir!(), "unsafe-grep-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp run(dir), do: System.cmd(@script, [dir], stderr_to_stdout: true)

  for form <- @forms do
    test "finds #{form}", %{dir: dir} do
      File.write!(
        Path.join(dir, "probe.ex"),
        "defmodule P do\n  def a(x), do: #{unquote(form)}\nend\n"
      )

      assert {_, 1} = run(dir)
    end
  end

  # Interpolated word sigil with the atom modifier: it expands to String.to_atom/1.
  @word_sigils_with_atoms [
    ~S|~w(#{x})a|,
    ~S|~w[#{x}]a|,
    ~S|~w{#{x}}a|,
    ~S|~w/#{x}/a|,
    ~S(~w|#{x}|a),
    ~S|~w"#{x}"a|,
    ~S|~w'#{x}'a|
  ]

  for form <- @word_sigils_with_atoms do
    test "finds #{form}", %{dir: dir} do
      File.write!(
        Path.join(dir, "probe.ex"),
        "defmodule P do\n  def a(x), do: #{unquote(form)}\nend\n"
      )

      assert {_, 1} = run(dir)
    end
  end

  for form <- [~S|~w(a b)a|, ~S|~W(#{x})a|, ~S|~w(#{x})|] do
    test "passes #{form}", %{dir: dir} do
      File.write!(
        Path.join(dir, "probe.ex"),
        "defmodule P do\n  def a(x), do: #{unquote(form)}\nend\n"
      )

      assert {out, 0} = run(dir)
      assert out =~ "unsafe-grep: ok"
    end
  end

  test "finds raw in a heex template", %{dir: dir} do
    File.write!(Path.join(dir, "probe.heex"), "<div>{@x |> raw}</div>\n")
    assert {_, 1} = run(dir)
  end

  test "passes a clean file", %{dir: dir} do
    File.write!(
      Path.join(dir, "clean.ex"),
      "defmodule C do\n  def a(x), do: Phoenix.HTML.html_escape(x)\nend\n"
    )

    assert {out, 0} = run(dir)
    assert out =~ "unsafe-grep: ok"
  end
end
