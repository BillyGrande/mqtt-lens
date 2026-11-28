defmodule MqttLens.CiWorkflowTest do
  # Contract of .github/workflows/ci.yml (ml-1a7.5):
  #   1 (ml-1a7.4.6) The actions/cache paths exclude the tool binaries
  #     (_build/tailwind-* and _build/esbuild-*). A cache hit never brings a binary
  #     that runs before scripts/ci/tool-sums.sh checks it.
  #   2 (ml-1a7.4.4) The test-tamper step runs the BASE copy of the gate:
  #     git show "<base sha>:scripts/ci/test-tamper.sh" into $RUNNER_TEMP, then bash
  #     runs that file. The values come through env only. If BASE has no such file,
  #     the step fails.
  #   3 (ml-1a7.5.4) The step fails (non-zero) when the BASE value is empty or unset,
  #     before it runs git show. An empty BASE makes ":scripts/ci/test-tamper.sh",
  #     which reads the index (PR) copy.
  # The file is read as text with a small parser for the step blocks (no YAML library
  # in the deps).
  use ExUnit.Case, async: true

  @ci_yml Path.expand("../../.github/workflows/ci.yml", __DIR__)

  @git_env [
    {"GIT_CONFIG_GLOBAL", "/dev/null"},
    {"GIT_CONFIG_NOSYSTEM", "1"},
    {"GIT_AUTHOR_NAME", "Test Author"},
    {"GIT_AUTHOR_EMAIL", "test@example.invalid"},
    {"GIT_COMMITTER_NAME", "Test Author"},
    {"GIT_COMMITTER_EMAIL", "test@example.invalid"}
  ]

  # The binary names that `mix assets.setup` writes on the CI runner (linux x64).
  @binaries ["_build/tailwind-linux-x64", "_build/esbuild-linux-x64"]

  @base_sha_expr ~r/\A\$\{\{\s*github\.event\.pull_request\.base\.sha\s*\}\}\z/
  @head_sha_expr ~r/\A\$\{\{\s*github\.event\.pull_request\.head\.sha\s*\}\}\z/

  # --- minimal parser for the steps of the workflow ----------------------------

  defp steps do
    lines = @ci_yml |> File.read!() |> String.split("\n")
    chunk_steps(lines, [])
  end

  defp chunk_steps([], acc), do: Enum.reverse(acc)

  defp chunk_steps([line | rest], acc) do
    case Regex.run(~r/^(\s+)- ([A-Za-z0-9_-]+:.*)$/, line) do
      [_, ind, first] ->
        n = String.length(ind)

        {body, rest2} =
          Enum.split_while(rest, &(blank?(&1) or (indent(&1) > n and not item_at?(&1, n))))

        key_line = String.duplicate(" ", n + 2) <> first
        chunk_steps(rest2, [parse_map([key_line | body], n + 2) | acc])

      nil ->
        chunk_steps(rest, acc)
    end
  end

  defp item_at?(line, n), do: Regex.match?(~r/^\s{#{n}}- /, line)
  defp blank?(line), do: String.trim(line) == ""
  defp indent(line), do: String.length(line) - String.length(String.trim_leading(line))

  # Parses the keys at indentation n. A value is a string (plain scalar or block
  # scalar) or a nested map.
  defp parse_map(lines, n), do: parse_map(lines, n, %{})

  defp parse_map([], _n, acc), do: acc

  defp parse_map([line | rest], n, acc) do
    case Regex.run(~r/^\s{#{n}}([A-Za-z0-9_-]+):\s?(.*)$/, line) do
      [_, key, value] ->
        {children, rest2} = Enum.split_while(rest, &(blank?(&1) or indent(&1) > n))
        parse_map(rest2, n, Map.put(acc, key, value(String.trim(value), children)))

      nil ->
        parse_map(rest, n, acc)
    end
  end

  defp value(v, children) when v in ["|", "|-", ">", ">-"], do: dedent(children)

  defp value("", children) do
    case Enum.reject(children, &blank?/1) do
      [] -> ""
      [first | _] = kids -> parse_map(kids, indent(first))
    end
  end

  defp value(v, _children) do
    v
    |> String.replace(~r/\s+#.*$/, "")
    |> String.trim()
    |> unquote_scalar()
  end

  defp unquote_scalar(<<q, rest::binary>> = v) when q in [?", ?'] do
    if String.ends_with?(rest, <<q>>), do: String.slice(rest, 0..-2//1), else: v
  end

  defp unquote_scalar(v), do: v

  defp dedent(children) do
    children = Enum.reverse(Enum.drop_while(Enum.reverse(children), &blank?/1))
    n = children |> Enum.reject(&blank?/1) |> Enum.map(&indent/1) |> Enum.min(fn -> 0 end)
    Enum.map_join(children, "\n", &String.slice(&1, n..-1//1))
  end

  defp tamper_step do
    case Enum.filter(steps(), &(is_binary(&1["run"]) and &1["run"] =~ "test-tamper.sh")) do
      [step] -> step
      other -> flunk("expected one step that runs test-tamper.sh, found #{length(other)}")
    end
  end

  defp env_var(step, expr) do
    case Enum.find(Map.get(step, "env", %{}), fn {_k, v} -> is_binary(v) and v =~ expr end) do
      {k, _} -> k
      nil -> flunk("the test-tamper step has no env value #{inspect(expr.source)}")
    end
  end

  # --- glob match as in actions/cache (@actions/glob, implicitDescendants: false)

  defp normalize(pattern) do
    pattern |> String.trim_leading("./") |> String.trim_trailing("/")
  end

  defp glob_match?(pattern, path) do
    p = normalize(pattern)

    cond do
      p in [".", ""] ->
        true

      String.ends_with?(p, "/**") and glob_match?(String.trim_trailing(p, "/**"), path) ->
        true

      true ->
        body =
          p
          |> String.split("**")
          |> Enum.map_join(".*", fn part ->
            part
            |> Regex.escape()
            |> String.replace("\\*", "[^/]*")
            |> String.replace("\\?", "[^/]")
          end)

        Regex.match?(Regex.compile!("\\A" <> body <> "\\z"), path)
    end
  end

  defp cache_paths do
    cache_steps =
      Enum.filter(
        steps(),
        &(is_binary(&1["uses"]) and String.starts_with?(&1["uses"], "actions/cache@"))
      )

    if cache_steps == [], do: flunk("ci.yml has no actions/cache step")

    for step <- cache_steps do
      path = get_in(step, ["with", "path"]) || flunk("an actions/cache step has no path")

      path
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    end
  end

  # --- helpers for the run of the step in a temporary repository -------------

  defp git(repo, args) do
    {out, 0} = System.cmd("git", args, cd: repo, env: @git_env, stderr_to_stdout: true)
    String.trim(out)
  end

  defp write(repo, path, content) do
    full = Path.join(repo, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
    File.chmod!(full, 0o755)
  end

  defp commit(repo, message) do
    git(repo, ["add", "-A"])
    git(repo, ["commit", "-q", "-m", message])
    git(repo, ["rev-parse", "HEAD"])
  end

  @script "scripts/ci/test-tamper.sh"
  @head_copy "#!/usr/bin/env bash\necho HEAD-COPY-8J1\nexit 0\n"

  # GitHub runs a run: script with "bash -e {0}" when the step sets no shell, and
  # with "bash --noprofile --norc -eo pipefail {0}" for "shell: bash".
  defp shell_args(step) do
    case step["shell"] do
      nil -> ["-e"]
      "bash" -> ["--noprofile", "--norc", "-eo", "pipefail"]
      other -> flunk("unexpected shell for the test-tamper step: #{inspect(other)}")
    end
  end

  defp run_step(repo, temp, base, head) do
    step = tamper_step()

    env =
      for {k, v} <- Map.get(step, "env", %{}), is_binary(v) do
        cond do
          v =~ @base_sha_expr -> {k, base}
          v =~ @head_sha_expr -> {k, head}
          v =~ "${{" -> {k, ""}
          true -> {k, v}
        end
      end

    file = Path.join(temp, "step-#{System.unique_integer([:positive])}.sh")
    File.write!(file, step["run"] <> "\n")
    runner_temp = Path.join(temp, "runner")
    File.mkdir_p!(runner_temp)

    System.cmd("bash", shell_args(step) ++ [file],
      cd: repo,
      env: @git_env ++ env ++ [{"RUNNER_TEMP", runner_temp}],
      stderr_to_stdout: true
    )
  end

  describe "CI cache never restores the tool binaries (ml-1a7.4.6)" do
    test "the parser finds the actions/cache path list" do
      for paths <- cache_paths() do
        assert "deps" in paths
      end
    end

    test "each actions/cache path list excludes _build/tailwind-* and _build/esbuild-*" do
      for paths <- cache_paths(), binary <- @binaries do
        exclusions = for "!" <> p <- paths, do: p

        assert Enum.any?(exclusions, &glob_match?(&1, binary)),
               "no exclusion (!...) in the cache path matches #{binary}: #{inspect(paths)}"
      end
    end

    test "no cache path includes the whole _build folder (an exclusion does not work inside it)" do
      for paths <- cache_paths(), include <- paths, not String.starts_with?(include, "!") do
        refute glob_match?(include, "_build"),
               "the cache path #{inspect(include)} includes the whole _build folder, " <>
                 "so the tool binaries are in the cache"
      end
    end

    test "the last cache pattern that matches a tool binary is an exclusion" do
      for paths <- cache_paths(), binary <- @binaries do
        last =
          paths
          |> Enum.filter(fn
            "!" <> p -> glob_match?(p, binary)
            p -> glob_match?(p, binary)
          end)
          |> List.last()

        assert last == nil or String.starts_with?(last, "!"),
               "#{binary} is in the cache (last matching pattern: #{inspect(last)})"
      end
    end
  end

  describe "CI runs the BASE copy of test-tamper.sh (ml-1a7.4.4)" do
    test "the step runs on pull_request only" do
      assert tamper_step()["if"] =~ ~r/github\.event_name\s*==\s*'pull_request'/
    end

    test "the run script gets the SHAs through env only, with no expression in run" do
      step = tamper_step()
      env_var(step, @base_sha_expr)
      env_var(step, @head_sha_expr)
      refute step["run"] =~ "${{"
    end

    test "the run script writes the BASE blob of the script into RUNNER_TEMP and runs it with bash" do
      step = tamper_step()
      run = step["run"]
      var = env_var(step, @base_sha_expr)

      assert run =~
               ~r/git show "\$\{?#{var}\}?:scripts\/ci\/test-tamper\.sh"\s*>\s*"\$\{?RUNNER_TEMP\}?\//,
             "the step does not write git show \"$#{var}:scripts/ci/test-tamper.sh\" into $RUNNER_TEMP"

      assert run =~ ~r/(^|[\s;&|])bash\s+"\$\{?RUNNER_TEMP\}?\//m,
             "the step does not run the RUNNER_TEMP copy with bash"
    end

    test "the run script does not run the PR copy of the script" do
      run = tamper_step()["run"]

      code =
        run
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))
        |> Enum.join("\n")
        |> String.replace(~r/git show "[^"]*:scripts\/ci\/test-tamper\.sh"/, "")

      refute code =~ "scripts/ci/test-tamper.sh",
             "the step names scripts/ci/test-tamper.sh outside the git show of the BASE blob"
    end
  end

  describe "the test-tamper step, run in a temporary repository (ml-1a7.4.4)" do
    setup do
      repo = Path.join(System.tmp_dir!(), "ci-workflow-#{System.unique_integer([:positive])}")
      temp = repo <> "-runner-temp"
      File.mkdir_p!(repo)
      File.mkdir_p!(temp)

      on_exit(fn ->
        File.rm_rf!(repo)
        File.rm_rf!(temp)
      end)

      git(repo, ["init", "-q", "-b", "main"])
      git(repo, ["config", "gc.auto", "0"])
      {:ok, repo: repo, temp: temp}
    end

    test "runs the BASE copy with BASE and HEAD, not the PR copy",
         %{repo: repo, temp: temp} do
      write(repo, @script, "#!/usr/bin/env bash\necho \"BASE-COPY-3F7 $1 $2\"\nexit 0\n")
      base = commit(repo, "ci: base gate")
      write(repo, @script, @head_copy)
      head = commit(repo, "ci: PR gate")

      assert {out, 0} = run_step(repo, temp, base, head)
      assert out =~ "BASE-COPY-3F7 #{base} #{head}"
      refute out =~ "HEAD-COPY-8J1"
    end

    test "fails when the BASE copy fails, also when the PR copy passes",
         %{repo: repo, temp: temp} do
      write(repo, @script, "#!/usr/bin/env bash\necho BASE-FAIL-5D2\nexit 1\n")
      base = commit(repo, "ci: base gate")
      write(repo, @script, @head_copy)
      head = commit(repo, "ci: PR gate")

      assert {out, code} = run_step(repo, temp, base, head)
      assert code != 0
      refute out =~ "HEAD-COPY-8J1"
    end

    test "fails when BASE has no scripts/ci/test-tamper.sh", %{repo: repo, temp: temp} do
      write(repo, "README.md", "probe\n")
      base = commit(repo, "chore: base")
      write(repo, @script, @head_copy)
      head = commit(repo, "ci: PR gate")

      assert {out, code} = run_step(repo, temp, base, head)
      assert code != 0
      refute out =~ "HEAD-COPY-8J1"
    end
  end

  # --- ml-1a7.5.4 ---------------------------------------------------------------

  # Runs the step as run_step/4 does, but sets the BASE env value to base_value
  # (nil = unset) and puts a git wrapper first on PATH. The wrapper writes each git
  # command line to a log file, then runs the real git. Returns {out, code, log}.
  defp run_step_logged(repo, temp, base_value, head) do
    step = tamper_step()
    base_var = env_var(step, @base_sha_expr)

    env =
      for {k, v} <- Map.get(step, "env", %{}), is_binary(v) do
        cond do
          k == base_var -> {k, base_value}
          v =~ @head_sha_expr -> {k, head}
          v =~ "${{" -> {k, ""}
          true -> {k, v}
        end
      end

    real_git = System.find_executable("git") || flunk("git is not on PATH")
    bin = Path.join(temp, "bin-#{System.unique_integer([:positive])}")
    log = Path.join(temp, "git-#{System.unique_integer([:positive])}.log")
    File.mkdir_p!(bin)
    File.write!(log, "")

    File.write!(
      Path.join(bin, "git"),
      "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> '#{log}'\nexec '#{real_git}' \"$@\"\n"
    )

    File.chmod!(Path.join(bin, "git"), 0o755)

    file = Path.join(temp, "step-#{System.unique_integer([:positive])}.sh")
    File.write!(file, step["run"] <> "\n")
    runner_temp = Path.join(temp, "runner")
    File.mkdir_p!(runner_temp)

    {out, code} =
      System.cmd("bash", shell_args(step) ++ [file],
        cd: repo,
        env:
          @git_env ++
            env ++
            [{"RUNNER_TEMP", runner_temp}, {"PATH", bin <> ":" <> System.get_env("PATH", "")}],
        stderr_to_stdout: true
      )

    {out, code, File.read!(log)}
  end

  defp git_show_called?(log) do
    log |> String.split("\n") |> Enum.any?(&String.starts_with?(&1, "show"))
  end

  describe "the test-tamper step with an empty or unset BASE value (ml-1a7.5.4)" do
    setup do
      repo = Path.join(System.tmp_dir!(), "ci-workflow-#{System.unique_integer([:positive])}")
      temp = repo <> "-runner-temp"
      File.mkdir_p!(repo)
      File.mkdir_p!(temp)

      on_exit(fn ->
        File.rm_rf!(repo)
        File.rm_rf!(temp)
      end)

      git(repo, ["init", "-q", "-b", "main"])
      git(repo, ["config", "gc.auto", "0"])
      write(repo, @script, "#!/usr/bin/env bash\necho \"BASE-COPY-3F7 $1 $2\"\nexit 0\n")
      base = commit(repo, "ci: base gate")
      # The index and HEAD hold the PR copy. "git show :<path>" (empty BASE) reads it.
      write(repo, @script, @head_copy)
      head = commit(repo, "ci: PR gate")
      {:ok, repo: repo, temp: temp, base: base, head: head}
    end

    test "the git wrapper logs git show when the BASE value is set",
         %{repo: repo, temp: temp, base: base, head: head} do
      assert {out, 0, log} = run_step_logged(repo, temp, base, head)
      assert out =~ "BASE-COPY-3F7"
      assert git_show_called?(log), "the git wrapper did not log git show: #{inspect(log)}"
    end

    test "fails before git show when the BASE value is empty",
         %{repo: repo, temp: temp, head: head} do
      assert {out, code, log} = run_step_logged(repo, temp, "", head)
      assert code != 0
      refute out =~ "HEAD-COPY-8J1"
      refute git_show_called?(log), "the step ran git show with an empty BASE value"
    end

    test "fails before git show when the BASE value is unset",
         %{repo: repo, temp: temp, head: head} do
      assert {out, code, log} = run_step_logged(repo, temp, nil, head)
      assert code != 0
      refute out =~ "HEAD-COPY-8J1"
      refute git_show_called?(log), "the step ran git show with no BASE value"
    end
  end
end
