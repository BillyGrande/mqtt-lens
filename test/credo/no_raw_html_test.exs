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
