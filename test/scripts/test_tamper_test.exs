defmodule MqttLens.TestTamperScriptTest do
  # Contract of scripts/ci/test-tamper.sh (ml-1a7.4):
  #   scripts/ci/test-tamper.sh BASE HEAD
  # It reads the git repository of the current directory. Exit 0 = pass, exit 1 = fail.
  # The files that a "Tests-Committed: <id>" commit added are frozen for the later
  # commits in BASE..HEAD that have no such trailer line.
  use ExUnit.Case, async: true

  @script Path.expand("../../scripts/ci/test-tamper.sh", __DIR__)
  @ci_yml Path.expand("../../.github/workflows/ci.yml", __DIR__)

  @git_env [
    {"GIT_CONFIG_GLOBAL", "/dev/null"},
    {"GIT_CONFIG_NOSYSTEM", "1"},
    {"GIT_AUTHOR_NAME", "Test Author"},
    {"GIT_AUTHOR_EMAIL", "test@example.invalid"},
    {"GIT_COMMITTER_NAME", "Test Author"},
    {"GIT_COMMITTER_EMAIL", "test@example.invalid"}
  ]

  @frozen "test/probe_test.exs"
  @trailer "test: probe tests (ml-x.1)\n\nTests-Committed: ml-x.1"

  setup do
    repo = Path.join(System.tmp_dir!(), "test-tamper-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)

    git(repo, ["init", "-q", "-b", "main"])
    git(repo, ["config", "gc.auto", "0"])
    write(repo, "README.md", "probe\n")
    base = commit(repo, "chore: base")
    {:ok, repo: repo, base: base}
  end

  defp git(repo, args) do
    {out, 0} = System.cmd("git", args, cd: repo, env: @git_env, stderr_to_stdout: true)
    String.trim(out)
  end

  defp write(repo, path, content) do
    full = Path.join(repo, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
  end

  defp commit(repo, message) do
    git(repo, ["add", "-A"])
    git(repo, ["commit", "-q", "-m", message])
    git(repo, ["rev-parse", "HEAD"])
  end

  # Adds the frozen test file in a commit with the trailer. Returns the SHA.
  defp tests_committed(repo) do
    write(repo, @frozen, "defmodule ProbeTest do\n  # FROZEN-BODY-7Q2\nend\n")
    commit(repo, @trailer)
  end

  defp head(repo), do: git(repo, ["rev-parse", "HEAD"])

  defp run(repo, args),
    do: System.cmd(@script, args, cd: repo, env: @git_env, stderr_to_stdout: true)

  defp run(repo, base, head), do: run(repo, [base, head])

  defp loose_object(repo, sha) do
    {prefix, rest} = String.split_at(sha, 2)
    Path.join([repo, ".git", "objects", prefix, rest])
  end

  describe "frozen files" do
    test "fails when a later commit without the trailer modifies a frozen file",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, "defmodule ProbeTest do\n  # weakened\nend\n")
      bad = commit(repo, "fix: weaken the test")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @frozen
      assert out =~ String.slice(bad, 0, 7)
    end

    test "fails when a later commit without the trailer deletes a frozen file",
         %{repo: repo, base: base} do
      tests_committed(repo)
      File.rm!(Path.join(repo, @frozen))
      commit(repo, "fix: drop the test")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @frozen
    end

    test "fails when a later commit without the trailer renames a frozen file",
         %{repo: repo, base: base} do
      tests_committed(repo)
      git(repo, ["mv", @frozen, "test/renamed_test.exs"])
      commit(repo, "refactor: rename the test")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @frozen
    end

    test "fails when a frozen file is changed and later changed back",
         %{repo: repo, base: base} do
      tests_committed(repo)
      original = File.read!(Path.join(repo, @frozen))
      write(repo, @frozen, "defmodule ProbeTest do\nend\n")
      commit(repo, "fix: weaken the test")
      write(repo, @frozen, original)
      commit(repo, "fix: restore the test")

      assert {_, 1} = run(repo, base, head(repo))
    end

    test "fails when the trailer text is not at the start of a line",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, "defmodule ProbeTest do\n  # weakened\nend\n")
      commit(repo, "fix: weaken the test (not Tests-Committed: ml-x.1)")

      assert {_, 1} = run(repo, base, head(repo))
    end

    test "prints paths and short SHAs only, not file content or full SHAs",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, "defmodule ProbeTest do\n  # TAMPERED-BODY-9K4\nend\n")
      bad = commit(repo, "fix: weaken the test")

      assert {out, 1} = run(repo, base, head(repo))
      refute out =~ "FROZEN-BODY-7Q2"
      refute out =~ "TAMPERED-BODY-9K4"
      refute out =~ bad
    end
  end

  describe "allowed changes" do
    test "passes when a later commit with the trailer changes a frozen file",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, "defmodule ProbeTest do\n  # more cases\nend\n")
      commit(repo, "test: more probe cases (ml-x.1)\n\nTests-Committed: ml-x.1")

      assert {_, 0} = run(repo, base, head(repo))
    end

    test "passes when later commits without the trailer change other files only",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      commit(repo, "feat: probe")
      write(repo, "test/other_test.exs", "defmodule OtherTest do\nend\n")
      commit(repo, "test: other")

      assert {_, 0} = run(repo, base, head(repo))
    end

    test "freezes the files of each trailer commit", %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, "defmodule ProbeTest do\n  # more cases\nend\n")
      write(repo, "test/second_test.exs", "defmodule SecondTest do\nend\n")
      commit(repo, "test: second (ml-x.2)\n\nTests-Committed: ml-x.2")
      write(repo, "test/second_test.exs", "defmodule SecondTest do\n  # weakened\nend\n")
      commit(repo, "fix: weaken the second test")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ "test/second_test.exs"
    end

    test "passes with a notice when the range has no trailer commit",
         %{repo: repo, base: base} do
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      commit(repo, "feat: probe")

      assert {out, 0} = run(repo, base, head(repo))
      assert out =~ "Tests-Committed"
    end
  end

  describe "merge commits" do
    test "fails when the range contains a merge commit", %{repo: repo, base: base} do
      tests_committed(repo)
      git(repo, ["checkout", "-q", "-b", "side"])
      write(repo, "lib/side.ex", "defmodule Side do\nend\n")
      commit(repo, "feat: side")
      git(repo, ["checkout", "-q", "main"])
      write(repo, "lib/main.ex", "defmodule Main do\nend\n")
      commit(repo, "feat: main")
      git(repo, ["merge", "-q", "--no-ff", "-m", "merge side", "side"])

      assert {_, 1} = run(repo, base, head(repo))
    end

    test "fails on a merge commit also when the range has no trailer commit",
         %{repo: repo, base: base} do
      git(repo, ["checkout", "-q", "-b", "side"])
      write(repo, "lib/side.ex", "defmodule Side do\nend\n")
      commit(repo, "feat: side")
      git(repo, ["checkout", "-q", "main"])
      write(repo, "lib/main.ex", "defmodule Main do\nend\n")
      commit(repo, "feat: main")
      git(repo, ["merge", "-q", "--no-ff", "-m", "merge side", "side"])

      assert {_, 1} = run(repo, base, head(repo))
    end
  end

  describe "fail closed" do
    test "fails on a bad BASE", %{repo: repo} do
      tests_committed(repo)
      assert {_, 1} = run(repo, "no-such-ref", head(repo))
    end

    test "fails on a bad HEAD", %{repo: repo, base: base} do
      tests_committed(repo)
      assert {_, 1} = run(repo, base, "no-such-ref")
    end

    test "fails on an unknown full SHA as BASE", %{repo: repo} do
      tests_committed(repo)
      assert {_, 1} = run(repo, String.duplicate("a", 40), head(repo))
    end

    test "fails when the arguments are missing", %{repo: repo} do
      assert {_, code} = run(repo, [])
      assert code != 0
    end

    test "fails outside a git repository", %{repo: repo, base: base} do
      plain = repo <> "-plain"
      File.mkdir_p!(plain)
      on_exit(fn -> File.rm_rf!(plain) end)

      assert {_, 1} = run(plain, base, base)
    end

    test "fails when a commit in the range is unreadable", %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      middle = commit(repo, "feat: probe")
      write(repo, "lib/probe2.ex", "defmodule Probe2 do\nend\n")
      top = commit(repo, "feat: probe2")
      File.rm!(loose_object(repo, middle))

      assert {_, 1} = run(repo, base, top)
    end

    test "fails when the tree of a later commit is unreadable", %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      later = commit(repo, "feat: probe")
      File.rm!(loose_object(repo, git(repo, ["rev-parse", later <> "^{tree}"])))

      assert {_, 1} = run(repo, base, later)
    end

    test "fails when the tree of the trailer commit is unreadable",
         %{repo: repo, base: base} do
      trailer = tests_committed(repo)
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      later = commit(repo, "feat: probe")
      File.rm!(loose_object(repo, git(repo, ["rev-parse", trailer <> "^{tree}"])))

      assert {_, 1} = run(repo, base, later)
    end
  end

  test "CI runs the test-tamper check" do
    assert File.read!(@ci_yml) =~ "scripts/ci/test-tamper.sh"
  end
end
