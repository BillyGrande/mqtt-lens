Code.require_file("../../.credo/checks/no_raw_html.ex", __DIR__)
Application.ensure_all_started(:credo)

defmodule MqttLens.Credo.NoRawHtmlTest do
  use Credo.Test.Case, async: true

  alias MqttLens.Credo.NoRawHtml

  test "flags raw/1" do
    """
    defmodule Sample do
      def a(x), do: raw(x)
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags Phoenix.HTML.raw/1" do
    """
    defmodule Sample do
      def a(x), do: Phoenix.HTML.raw(x)
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags x |> raw()" do
    """
    defmodule Sample do
      def a(x), do: x |> raw()
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags x |> Phoenix.HTML.raw()" do
    """
    defmodule Sample do
      def a(x), do: x |> Phoenix.HTML.raw()
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags {:safe, _}" do
    """
    defmodule Sample do
      def a(x), do: {:safe, x}
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags x |> raw (no parens)" do
    """
    defmodule Sample do
      def a(x), do: x |> raw
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags x |> Phoenix.HTML.raw (no parens)" do
    """
    defmodule Sample do
      def a(x), do: x |> Phoenix.HTML.raw
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags &raw/1 capture" do
    """
    defmodule Sample do
      def a(x), do: Enum.map(x, &raw/1)
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags &Phoenix.HTML.raw/1 capture" do
    """
    defmodule Sample do
      def a(x), do: Enum.map(x, &Phoenix.HTML.raw/1)
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags apply(Phoenix.HTML, :raw, ...)" do
    """
    defmodule Sample do
      def a(x), do: apply(Phoenix.HTML, :raw, [x])
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags String.to_atom(x)" do
    """
    defmodule Sample do
      def a(x), do: String.to_atom(x)
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags x |> String.to_atom" do
    """
    defmodule Sample do
      def a(x), do: x |> String.to_atom
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags &String.to_atom/1 capture" do
    """
    defmodule Sample do
      def a(x), do: Enum.map(x, &String.to_atom/1)
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "flags apply(String, :to_atom, ...)" do
    """
    defmodule Sample do
      def a(x), do: apply(String, :to_atom, [x])
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> assert_issue()
  end

  test "passes clean code" do
    """
    defmodule Sample do
      def a(x), do: Phoenix.HTML.html_escape(x)
    end
    """
    |> to_source_file()
    |> run_check(NoRawHtml)
    |> refute_issues()
  end
end
