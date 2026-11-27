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

  # Any reference to the name raw: call, pipe without parens (`x |> raw`) or capture
  # (`&raw/1`). In the AST all of them are a node {:raw, meta, args}, args a list or nil.
  defp walk({:raw, meta, args} = ast, ctx) when is_list(args) or is_nil(args),
    do: {ast, put_issue(ctx, issue_for(ctx, meta[:line], "raw"))}

  # Phoenix.HTML.raw(x), x |> Phoenix.HTML.raw, &Phoenix.HTML.raw/1
  defp walk({{:., _, [_, :raw]}, meta, args} = ast, ctx) when is_list(args),
    do: {ast, put_issue(ctx, issue_for(ctx, meta[:line], "raw"))}

  # apply(Phoenix.HTML, :raw, args), apply(String, :to_atom, args)
  defp walk({:apply, meta, [_, name | _]} = ast, ctx) when name in [:raw, :to_atom],
    do: {ast, put_issue(ctx, issue_for(ctx, meta[:line], Atom.to_string(name)))}

  # Kernel.apply/3 and Function.capture/3 with :raw or :to_atom
  defp walk({{:., _, [{:__aliases__, _, [mod]}, fun]}, meta, [_, name | _]} = ast, ctx)
       when {mod, fun} in [{:Kernel, :apply}, {:Function, :capture}] and
              name in [:raw, :to_atom],
       do: {ast, put_issue(ctx, issue_for(ctx, meta[:line], Atom.to_string(name)))}

  # String.to_atom(x), x |> String.to_atom, &String.to_atom/1
  defp walk({{:., _, [{:__aliases__, _, [:String]}, :to_atom]}, meta, args} = ast, ctx)
       when is_list(args),
       do: {ast, put_issue(ctx, issue_for(ctx, meta[:line], "String.to_atom"))}

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
      message:
        "Do not use raw/1, {:safe, _} or String.to_atom: they switch off HTML escaping or grow the atom table.",
      trigger: trigger,
      line_no: line
    )
  end
end
