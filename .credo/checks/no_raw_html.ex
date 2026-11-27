defmodule MqttLens.Credo.NoRawHtml do
  @moduledoc false
  use Credo.Check,
    id: "ML0001",
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: """
      `raw/1` and `{:safe, _}` switch off HTML escaping. In this application all
      output is escaped by default (see specs/architecture/supply-chain.md).
      Do not use `raw/1` or build `{:safe, _}` tuples. If there is a real need,
      record a decision in `specs/decisions/` first.
      """
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    result.issues
  end

  # raw(...) and Phoenix.HTML.raw(...)
  defp walk({:raw, meta, [_]} = ast, ctx),
    do: {ast, put_issue(ctx, issue_for(ctx, meta[:line], "raw"))}

  defp walk({{:., _, [_, :raw]}, meta, [_]} = ast, ctx),
    do: {ast, put_issue(ctx, issue_for(ctx, meta[:line], "raw"))}

  # x |> raw()
  defp walk({:|>, _, [_, {:raw, meta, []}]} = ast, ctx),
    do: {ast, put_issue(ctx, issue_for(ctx, meta[:line], "raw"))}

  # {:safe, _}: a 2-tuple has no metadata, so take the line from the second element.
  # A keyword entry `safe: value` has the same shape and is flagged too.
  defp walk({:safe, value} = ast, ctx) do
    {ast, put_issue(ctx, issue_for(ctx, line_of(value), "{:safe,"))}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp line_of({_, meta, _}) when is_list(meta), do: meta[:line]
  defp line_of(_), do: nil

  defp issue_for(ctx, line, trigger) do
    format_issue(ctx,
      message: "Do not use raw/1 or {:safe, _}: it switches off HTML escaping.",
      trigger: trigger,
      line_no: line
    )
  end
end
