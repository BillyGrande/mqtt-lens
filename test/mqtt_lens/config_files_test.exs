defmodule MqttLens.ConfigFilesTest do
  @moduledoc """
  Security review finding ml-1a7.2.12 (PR #19).

  sobelow must scan the config parser `lib/mqtt_lens/config.ex`. Only the
  small file-read module `lib/mqtt_lens/config/files.ex` is in the sobelow
  `ignore_files` list. That module must do file reads only.

  The test reads `.sobelow-conf`, `lib/mqtt_lens/config/files.ex` and
  `lib/mqtt_lens/config.ex` from the repository root and parses them with
  `Code.string_to_quoted!/2`. It does not evaluate them.

  Rules for `files.ex`:

    * The file has exactly one top-level form: `defmodule MqttLens.Config.Files`.
    * The only remote calls are `File.read/1`, `File.dir?/1` and `Path.join/2`
      (calls, pipes and captures). Any other remote call fails, also calls on
      Erlang modules, on variables and on `Kernel`. String interpolation is a
      `Kernel.to_string/1` call, so it fails too.
    * Typespecs (`@spec`) can name remote types with no arguments, for
      example `Path.t()`.
    * The only module attributes are `@moduledoc`, `@doc` and `@spec`.
    * No local call to `import`, `require`, `alias`, `use`, `apply` or other
      forms in `@forbidden_locals`.
    * Each function (`def` or `defp`) calls `File.read/1` or `File.dir?/1`.
      There are at most 3 functions.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @sobelow_conf Path.join(@root, ".sobelow-conf")
  @files_ex "lib/mqtt_lens/config/files.ex"
  @config_ex "lib/mqtt_lens/config.ex"

  # Modules are alias parts as written in the source, for example [:File].
  # `Elixir.File` and `:"Elixir.File"` do not match, so they fail.
  @allowed_remote [{[:File], :read, 1}, {[:File], :dir?, 1}, {[:Path], :join, 2}]
  @file_read_calls [{[:File], :read, 1}, {[:File], :dir?, 1}]
  @allowed_attributes [:moduledoc, :doc, :spec]
  @max_functions 3

  @forbidden_locals ~w(import require alias use apply spawn spawn_link spawn_monitor
                       send defmacro defmacrop defdelegate defguard defguardp defimpl
                       defprotocol defstruct defexception defoverridable quote unquote
                       unquote_splicing var! binding defmodule)a

  # ---------------------------------------------------------------------------
  # AST checker for files.ex. It returns a list of violation strings.
  # ---------------------------------------------------------------------------

  defp violations(source) do
    {violations, _functions} = check(source)
    violations
  end

  # Returns {violations, %{{name, arity} => reads_file?}}.
  defp check(source) do
    case Code.string_to_quoted!(source, columns: true) do
      {:defmodule, _, [{:__aliases__, _, [:MqttLens, :Config, :Files]}, [do: body]]} ->
        {_, acc} = Macro.prewalk(body, %{violations: [], functions: %{}}, &visit/2)
        {Enum.reverse(acc.violations) ++ function_violations(acc.functions), acc.functions}

      other ->
        {["top level must be exactly `defmodule MqttLens.Config.Files`, got: " <> short(other)],
         %{}}
    end
  end

  defp function_violations(functions) do
    too_many =
      if map_size(functions) > @max_functions,
        do: ["defines #{map_size(functions)} functions (max #{@max_functions})"],
        else: []

    no_read =
      for {{name, arity}, false} <- functions do
        "function #{name}/#{arity} does not call File.read/1 or File.dir?/1"
      end

    too_many ++ Enum.sort(no_read)
  end

  # Typespecs: only remote types with no arguments, for example Path.t().
  defp visit({:@, _, [{:spec, _, args}]}, acc) do
    {_, acc} = Macro.prewalk(args, acc, &visit_spec/2)
    {:skipped, acc}
  end

  defp visit({:@, _, [{name, _, _}]} = node, acc) when name in @allowed_attributes,
    do: {node, acc}

  defp visit({:@, _, [{name, _, _}]}, acc) when is_atom(name),
    do: {:skipped, add(acc, "module attribute @#{name} is not allowed")}

  # Function definitions: record each function and if it reads a file.
  defp visit({kind, _, [head, [do: body]]}, acc) when kind in [:def, :defp] do
    {name, arity, guard} = fun_head(head)
    reads? = reads_file?(body)
    functions = Map.update(acc.functions, {name, arity}, reads?, &(&1 or reads?))
    acc = %{acc | functions: functions}
    {_, acc} = Macro.prewalk({guard, body}, acc, &visit/2)
    {:skipped, acc}
  end

  defp visit({kind, _, _} = node, acc) when kind in [:def, :defp],
    do: {:skipped, add(acc, "unsupported function definition: " <> short(node))}

  # Pipes: `a |> M.f(b)` is the call `M.f(a, b)`.
  defp visit({:|>, _, [_lhs, {_, _, args}]} = node, acc) when is_list(args),
    do: visit(unpipe(node), acc)

  # Captures: `&M.f/n`.
  defp visit({:&, _, [{:/, _, [{{:., _, [mod, fun]}, _, []}, arity]}]}, acc)
       when is_atom(fun) and is_integer(arity),
       do: {:skipped, check_remote(acc, mod, fun, arity)}

  # Remote calls: `M.f(args)`, `:erl.f(args)`, `var.f(args)`.
  defp visit({{:., _, [mod, fun]}, _, args}, acc) when is_atom(fun) and is_list(args),
    do: {{:skipped, [], args}, check_remote(acc, mod, fun, length(args))}

  # Anonymous function calls and other dynamic calls: `f.(x)`.
  defp visit({{:., _, _}, _, _} = node, acc),
    do: {:skipped, add(acc, "dynamic call is not allowed: " <> short(node))}

  defp visit({name, _, args} = node, acc) when name in @forbidden_locals and is_list(args),
    do: {:skipped, add(acc, "local call #{name} is not allowed: " <> short(node))}

  defp visit(node, acc), do: {node, acc}

  defp unpipe({:|>, _, [lhs, {call, meta, args}]}), do: {call, meta, [lhs | args]}

  defp visit_spec({{:., _, [_mod, fun]}, _, []} = node, acc) when is_atom(fun),
    do: {node, acc}

  defp visit_spec({{:., _, _}, _, _} = node, acc),
    do: {:skipped, add(acc, "remote call with arguments in @spec: " <> short(node))}

  defp visit_spec(node, acc), do: {node, acc}

  defp fun_head({:when, _, [call, guard]}) do
    {name, arity, _} = fun_head(call)
    {name, arity, guard}
  end

  defp fun_head({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args), nil}

  defp fun_head({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {name, 0, nil}

  defp reads_file?(body) do
    {_, found?} = Macro.prewalk(body, false, &find_read/2)
    found?
  end

  defp find_read({:|>, _, [_lhs, {_, _, args}]} = node, found?) when is_list(args),
    do: find_read(unpipe(node), found?)

  defp find_read({{:., _, [mod, fun]}, _, args} = node, found?)
       when is_atom(fun) and is_list(args),
       do: {node, found? or {module_of(mod), fun, length(args)} in @file_read_calls}

  defp find_read(node, found?), do: {node, found?}

  defp check_remote(acc, mod, fun, arity) do
    mfa = {module_of(mod), fun, arity}

    if mfa in @allowed_remote,
      do: acc,
      else: add(acc, "remote call #{show_mfa(mfa)} is not allowed")
  end

  defp module_of({:__aliases__, _, parts}) when is_list(parts) do
    if Enum.all?(parts, &is_atom/1), do: parts, else: {:dynamic, parts}
  end

  defp module_of(mod) when is_atom(mod), do: mod
  defp module_of(other), do: {:dynamic, other}

  defp show_mfa({{:dynamic, mod}, fun, arity}), do: "#{short(mod)}.#{fun}/#{arity}"

  defp show_mfa({parts, fun, arity}) when is_list(parts),
    do: "#{Enum.join(parts, ".")}.#{fun}/#{arity}"

  defp show_mfa({mod, fun, arity}), do: "#{inspect(mod)}.#{fun}/#{arity}"

  defp add(acc, message), do: %{acc | violations: [message | acc.violations]}

  defp short(ast) do
    ast |> Macro.to_string() |> String.slice(0, 80)
  rescue
    _ -> inspect(ast, limit: 5)
  end

  defp read_repo_file!(relative) do
    path = Path.join(@root, relative)

    case File.read(path) do
      {:ok, content} -> content
      {:error, reason} -> flunk("#{relative} cannot be read: #{:file.format_error(reason)}")
    end
  end

  defp sobelow_conf! do
    conf = @sobelow_conf |> File.read!() |> Code.string_to_quoted!()
    assert Keyword.keyword?(conf), ".sobelow-conf must be a literal keyword list"
    conf
  end

  defp module_source(body) do
    "defmodule MqttLens.Config.Files do\n" <> body <> "\nend\n"
  end

  # ---------------------------------------------------------------------------
  # AC 1: ignore_files is exactly files.ex.
  # ---------------------------------------------------------------------------

  describe ".sobelow-conf" do
    test "ignore_files is exactly [\"lib/mqtt_lens/config/files.ex\"]" do
      assert Keyword.fetch(sobelow_conf!(), :ignore_files) == {:ok, [@files_ex]}
    end

    test "the ignored file exists" do
      assert File.regular?(Path.join(@root, @files_ex)), "#{@files_ex} does not exist"
    end

    # AC 3: sobelow scans config.ex.
    test "no ignore_files entry names config.ex or a directory that holds it" do
      entries = Keyword.get(sobelow_conf!(), :ignore_files, [])

      covering =
        Enum.filter(entries, fn entry ->
          entry = String.trim_trailing(entry, "/")
          entry == @config_ex or String.starts_with?(@config_ex, entry <> "/")
        end)

      assert covering == [], "ignore_files hides config.ex from sobelow: #{inspect(covering)}"
    end
  end

  # ---------------------------------------------------------------------------
  # AC 2: files.ex does file reads only.
  # ---------------------------------------------------------------------------

  describe "lib/mqtt_lens/config/files.ex" do
    test "calls only File.read/1, File.dir?/1 and Path.join/2 and defines only file-read functions" do
      source = read_repo_file!(@files_ex)
      assert violations(source) == []
    end

    test "defines at least one function that reads a file" do
      {_violations, functions} = check(read_repo_file!(@files_ex))
      assert map_size(functions) >= 1, "#{@files_ex} defines no file-read function"
    end
  end

  # AC 3 (the goal of the fix): config.ex has no direct file reads, so there is
  # nothing in it that needs an ignore.
  describe "lib/mqtt_lens/config.ex" do
    test "does not call File.read/1 or File.dir?/1 directly" do
      source = read_repo_file!(@config_ex)

      {_, direct} =
        source
        |> Code.string_to_quoted!()
        |> Macro.prewalk([], fn
          {{:., _, [{:__aliases__, _, [:File]}, fun]}, _, _} = node, found ->
            {node, [fun | found]}

          node, found ->
            {node, found}
        end)

      assert direct == [], "config.ex calls File.#{inspect(Enum.uniq(direct))} directly"
    end
  end

  # ---------------------------------------------------------------------------
  # Self-test of the checker, so the files.ex test cannot pass by accident.
  # ---------------------------------------------------------------------------

  describe "checker" do
    test "accepts a minimal file-read module" do
      source =
        module_source("""
          @moduledoc "File reads for MqttLens.Config."

          @doc "Read a file."
          @spec read(Path.t()) :: {:ok, binary()} | {:error, File.posix()}
          def read(path), do: File.read(path)

          @spec dir?(Path.t()) :: boolean()
          def dir?(path), do: File.dir?(path)

          @spec read_secret(Path.t(), String.t()) :: {:ok, binary()} | {:error, File.posix()}
          def read_secret(dir, name), do: dir |> Path.join(name) |> File.read()
        """)

      assert violations(source) == []
    end

    for {label, code} <- [
          {"System.cmd", "def read(p), do: {System.cmd(\"sh\", [p]), File.read(p)}"},
          {"Code.eval_string", "def read(p), do: {Code.eval_string(p), File.read(p)}"},
          {"erlang module", "def read(p), do: {:os.cmd(~c\"id\"), File.read(p)}"},
          {"File.write", "def read(p), do: {File.write(p, \"x\"), File.read(p)}"},
          {"File.read!", "def read(p), do: File.read!(p)"},
          {"Elixir.File alias", "def read(p), do: Elixir.File.read(p)"},
          {"Kernel remote", "def read(p), do: {Kernel.apply(System, :cmd, []), File.read(p)}"},
          {"local apply", "def read(p), do: {apply(System, :cmd, [p]), File.read(p)}"},
          {"import", "import System\ndef read(p), do: File.read(p)"},
          {"alias", "alias System, as: S\ndef read(p), do: File.read(p)"},
          {"capture", "def read(p), do: {&System.cmd/2, File.read(p)}"},
          {"pipe", "def read(p), do: {p |> System.cmd([]), File.read(p)}"},
          {"variable module", "def read(m, p), do: {m.cmd(p), File.read(p)}"},
          {"anonymous call", "def read(f, p), do: {f.(p), File.read(p)}"},
          {"interpolation", "def read(p), do: File.read(\"\#{p}\")"},
          {"attribute eval", "@x System.cmd(\"id\", [])\ndef read(p), do: File.read(p)"},
          {"on_load", "@on_load :read\ndef read, do: File.read(\"x\")"},
          {"spec call", "@spec read(System.cmd(1)) :: term()\ndef read(p), do: File.read(p)"},
          {"guard call", "def read(p) when :erlang.halt() == p, do: File.read(p)"},
          {"defmacro", "defmacro m(x), do: x\ndef read(p), do: File.read(p)"},
          {"nested module", "defmodule X do\nend\ndef read(p), do: File.read(p)"},
          {"extra function", "def read(p), do: File.read(p)\ndef parse(x), do: x"},
          {"extra private function", "def read(p), do: File.read(p)\ndefp helper(x), do: x"},
          {"too many functions",
           "def a(p), do: File.read(p)\ndef b(p), do: File.read(p)\n" <>
             "def c(p), do: File.read(p)\ndef d(p), do: File.dir?(p)"}
        ] do
      test "flags #{label}" do
        assert violations(module_source(unquote(code))) != []
      end
    end

    test "flags a wrong module name" do
      source = "defmodule MqttLens.Config.Other do\ndef read(p), do: File.read(p)\nend\n"
      assert violations(source) != []
    end

    test "flags top-level code outside the module" do
      source = module_source("def read(p), do: File.read(p)") <> "System.cmd(\"id\", [])\n"
      assert violations(source) != []
    end
  end
end
