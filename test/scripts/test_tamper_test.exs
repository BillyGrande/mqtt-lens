defmodule MqttLens.TestTamperScriptTest do
  # Contract of scripts/ci/test-tamper.sh (ml-1a7.4):
  #   scripts/ci/test-tamper.sh BASE HEAD
  # It reads the git repository of the current directory. Exit 0 = pass, exit 1 = fail.
  # The files that a "Tests-Committed: <id>" commit added are frozen for the later
  # commits in BASE..HEAD that have no such trailer line.
  # Hardened by ml-1a7.5:
  #   - Only a real git trailer counts (%(trailers:key=Tests-Committed,valueonly)), and
  #     its value must match the guard.sh pattern (one token, no white space).
  #   - After the first trailer commit, a commit without the trailer must not add,
  #     modify, delete, rename or change the mode of a path under test/ or of
  #     config/test.exs. Before it, such a commit must not add or change a path under
  #     test/.
  #   - A range with no trailer commit that changes a path under lib/ fails. A range
  #     that changes docs or scripts only passes with a notice.
  #   - A shallow repository fails.
  # Fix round 1 of ml-1a7.5:
  #   - Paths that git quotes (non-ASCII, double quote, backslash, tab, newline) are
  #     checked as raw paths, under test/ and lib/ (ml-1a7.5.1).
  #   - The trailer key counts only when it is exactly "Tests-Committed: " (case and
  #     space as written), as in .claude/hooks/guard.sh (ml-1a7.5.2).
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

    # ml-1a7.5 (stricter): was "passes when later commits without the trailer change
    # other files only" and expected exit 0. A commit without the trailer after the
    # trailer commit must not add a path under test/, so the result is now exit 1.
    test "fails when a later commit without the trailer adds another file under test/",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      commit(repo, "feat: probe")
      write(repo, "test/other_test.exs", "defmodule OtherTest do\nend\n")
      commit(repo, "test: other")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ "test/other_test.exs"
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

    # ml-1a7.5 (stricter): was "passes with a notice when the range has no trailer
    # commit" and expected exit 0 with a notice. A range with no trailer commit that
    # changes a path under lib/ now fails (exit 1).
    test "fails when the range has no trailer commit and changes lib/",
         %{repo: repo, base: base} do
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      commit(repo, "feat: probe")

      assert {out, 1} = run(repo, base, head(repo))
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

  # --- ml-1a7.5 ---------------------------------------------------------------

  @helper "test/test_helper.exs"
  @support "test/support/probe_case.ex"
  @config_test "config/test.exs"

  # Commits a test harness (test_helper, a support module, config/test.exs) and a lib
  # file. Returns the SHA. Use it as BASE, so these files exist before the range.
  defp harness(repo) do
    write(repo, @helper, "ExUnit.start()\n")
    write(repo, @support, "defmodule ProbeCase do\nend\n")
    write(repo, @config_test, "import Config\n")
    write(repo, "lib/app.ex", "defmodule App do\nend\n")
    commit(repo, "chore: harness")
  end

  defp shallow_clone(repo, depth) do
    clone = repo <> "-shallow"
    on_exit(fn -> File.rm_rf!(clone) end)

    {_, 0} =
      System.cmd(
        "git",
        ["clone", "-q", "--depth", "#{depth}", "--no-single-branch", "file://" <> repo, clone],
        env: @git_env,
        stderr_to_stdout: true
      )

    clone
  end

  describe "freeze of test/ and config/test.exs after the first trailer commit (ml-1a7.4.5)" do
    setup %{repo: repo} do
      {:ok, base: harness(repo)}
    end

    test "fails when a later commit without the trailer adds a file under test/",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, "test/extra_test.exs", "defmodule ExtraTest do\nend\n")
      bad = commit(repo, "fix: add a test")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ "test/extra_test.exs"
      assert out =~ String.slice(bad, 0, 7)
    end

    test "fails when a later commit without the trailer modifies test/test_helper.exs",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @helper, "ExUnit.start(exclude: [:test])\n")
      commit(repo, "fix: exclude the tests")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @helper
    end

    test "fails when a later commit without the trailer deletes a file under test/support/",
         %{repo: repo, base: base} do
      tests_committed(repo)
      File.rm!(Path.join(repo, @support))
      commit(repo, "fix: drop the case")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @support
    end

    test "fails when a later commit without the trailer renames a file under test/",
         %{repo: repo, base: base} do
      tests_committed(repo)
      git(repo, ["mv", @support, "test/support/renamed_case.ex"])
      commit(repo, "refactor: rename the case")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @support
    end

    test "fails when a later commit without the trailer changes only the mode of a test file",
         %{repo: repo, base: base} do
      tests_committed(repo)
      File.chmod!(Path.join(repo, @helper), 0o755)
      commit(repo, "chore: mode")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @helper
    end

    test "fails when a later commit without the trailer modifies a test file that the trailer commit modified",
         %{repo: repo, base: base} do
      write(repo, @helper, "ExUnit.start(capture_log: true)\n")
      tests_committed(repo)
      write(repo, @helper, "ExUnit.start()\n")
      commit(repo, "fix: revert the helper")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @helper
    end

    test "fails when a later commit without the trailer modifies config/test.exs",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @config_test, "import Config\nconfig :logger, level: :none\n")
      commit(repo, "chore: test config")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @config_test
    end

    test "fails when a later commit without the trailer deletes config/test.exs",
         %{repo: repo, base: base} do
      tests_committed(repo)
      File.rm!(Path.join(repo, @config_test))
      commit(repo, "chore: drop the test config")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @config_test
    end

    test "fails when a later commit without the trailer adds config/test.exs",
         %{repo: repo, base: base} do
      File.rm!(Path.join(repo, @config_test))
      tests_committed(repo)
      write(repo, @config_test, "import Config\n")
      commit(repo, "chore: add the test config")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @config_test
    end

    test "passes when a later commit without the trailer changes lib/, config/config.exs and paths that only contain the word test",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, "lib/app.ex", "defmodule App do\n  def x, do: 1\nend\n")
      write(repo, "lib/app/test/helper.ex", "defmodule App.Test.Helper do\nend\n")
      write(repo, "config/config.exs", "import Config\n")
      write(repo, "docs/test/notes.md", "notes\n")
      write(repo, "test_data.md", "data\n")
      commit(repo, "feat: app")

      assert {_, 0} = run(repo, base, head(repo))
    end
  end

  describe "test/ before the first trailer commit (ml-1a7.4.5)" do
    setup %{repo: repo} do
      {:ok, base: harness(repo)}
    end

    test "fails when a commit without the trailer adds a file under test/ before the trailer commit",
         %{repo: repo, base: base} do
      write(repo, "test/early_test.exs", "defmodule EarlyTest do\nend\n")
      bad = commit(repo, "test: early")
      tests_committed(repo)

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ "test/early_test.exs"
      assert out =~ String.slice(bad, 0, 7)
    end

    test "fails when a commit without the trailer modifies a file under test/ before the trailer commit",
         %{repo: repo, base: base} do
      write(repo, @helper, "ExUnit.start(exclude: [:test])\n")
      commit(repo, "chore: helper")
      tests_committed(repo)

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @helper
    end

    test "fails when a range with no trailer commit adds a file under test/",
         %{repo: repo, base: base} do
      write(repo, "test/early_test.exs", "defmodule EarlyTest do\nend\n")
      commit(repo, "test: early")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ "test/early_test.exs"
    end

    test "passes when a commit before the trailer commit changes lib/ only",
         %{repo: repo, base: base} do
      write(repo, "lib/app.ex", "defmodule App do\n  def x, do: 1\nend\n")
      commit(repo, "chore: prepare")
      tests_committed(repo)

      assert {_, 0} = run(repo, base, head(repo))
    end
  end

  describe "range with no trailer commit (ml-1a7.4.3)" do
    setup %{repo: repo} do
      {:ok, base: harness(repo)}
    end

    test "fails when a commit modifies a file under lib/", %{repo: repo, base: base} do
      write(repo, "lib/app.ex", "defmodule App do\n  def x, do: 1\nend\n")
      commit(repo, "feat: app")

      assert {_, 1} = run(repo, base, head(repo))
    end

    test "fails when a commit deletes a file under lib/", %{repo: repo, base: base} do
      File.rm!(Path.join(repo, "lib/app.ex"))
      commit(repo, "refactor: drop app")

      assert {_, 1} = run(repo, base, head(repo))
    end

    test "fails when a commit adds a file deep under lib/", %{repo: repo, base: base} do
      write(repo, "lib/mqtt_lens/deep/probe.ex", "defmodule Deep do\nend\n")
      commit(repo, "feat: deep")

      assert {_, 1} = run(repo, base, head(repo))
    end

    test "fails when only one of several commits changes lib/", %{repo: repo, base: base} do
      write(repo, "specs/notes.md", "notes\n")
      commit(repo, "docs: notes")
      write(repo, "lib/app.ex", "defmodule App do\n  def x, do: 1\nend\n")
      commit(repo, "feat: app")
      write(repo, "specs/more.md", "more\n")
      commit(repo, "docs: more")

      assert {_, 1} = run(repo, base, head(repo))
    end

    test "passes with a notice when the range changes docs only", %{repo: repo, base: base} do
      write(repo, "README.md", "probe, more\n")
      write(repo, "specs/notes.md", "notes\n")
      commit(repo, "docs: notes")

      assert {out, 0} = run(repo, base, head(repo))
      assert out =~ "Tests-Committed"
    end

    test "passes with a notice when the range changes scripts only",
         %{repo: repo, base: base} do
      write(repo, "scripts/ci/probe.sh", "#!/usr/bin/env bash\nexit 0\n")
      commit(repo, "ci: probe")

      assert {out, 0} = run(repo, base, head(repo))
      assert out =~ "Tests-Committed"
    end

    test "passes with a notice for paths that only contain the word lib",
         %{repo: repo, base: base} do
      write(repo, "docs/lib/notes.md", "notes\n")
      write(repo, "library.md", "library\n")
      commit(repo, "docs: lib notes")

      assert {out, 0} = run(repo, base, head(repo))
      assert out =~ "Tests-Committed"
    end
  end

  describe "only a real Tests-Committed trailer counts (ml-1a7.4.2)" do
    # Each case: a real trailer commit freezes the probe test. Then a commit with a
    # Tests-Committed text that is NOT a valid trailer changes the frozen file. That
    # commit counts as a commit without the trailer, so the gate must fail.
    @weakened "defmodule ProbeTest do\n  # weakened\nend\n"

    test "fails when the Tests-Committed text is the subject line",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, @weakened)
      commit(repo, "Tests-Committed: ml-x.1")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @frozen
    end

    test "fails when the Tests-Committed text is in a body paragraph that is not the trailer block",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, @weakened)
      commit(repo, "fix: weaken the test\n\nTests-Committed: ml-x.1\n\nMore prose after it.")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @frozen
    end

    test "fails when the trailer value is not one task-id token",
         %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, @weakened)
      commit(repo, "fix: weaken the test\n\nTests-Committed: ml x.1")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @frozen
    end

    test "fails when the trailer value is empty", %{repo: repo, base: base} do
      tests_committed(repo)
      write(repo, @frozen, @weakened)
      commit(repo, "fix: weaken the test\n\nTests-Committed:")

      assert {out, 1} = run(repo, base, head(repo))
      assert out =~ @frozen
    end

    test "treats a range whose only Tests-Committed text is in the body as a range with no trailer",
         %{repo: repo, base: base} do
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      commit(repo, "feat: probe\n\nTests-Committed: ml-x.1\n\nNot a trailer.")

      assert {_, 1} = run(repo, base, head(repo))
    end

    test "counts a trailer in a trailer block with other trailers",
         %{repo: repo, base: base} do
      write(repo, @frozen, "defmodule ProbeTest do\nend\n")

      commit(
        repo,
        "test: probe (ml-x.1)\n\nTests-Committed: ml-x.1\n" <>
          "Co-Authored-By: Probe <probe@example.invalid>\n" <>
          "Claude-Session: https://example.invalid/session"
      )

      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      commit(repo, "feat: probe")

      assert {out, 0} = run(repo, base, head(repo))
      assert out =~ "ok"
    end
  end

  describe "shallow repository (ml-1a7.4.9)" do
    test "fails in a shallow clone, also when BASE and HEAD are both present",
         %{repo: repo, base: base} do
      # Full history: a commit without the trailer weakens a frozen file, so the gate
      # fails. The shallow clone (depth 2) cuts that commit off, so a gate that does
      # not check for a shallow repository sees only a second trailer commit and a
      # docs commit.
      git(repo, ["branch", "base-ref", base])
      tests_committed(repo)
      write(repo, @frozen, "defmodule ProbeTest do\n  # weakened\nend\n")
      commit(repo, "fix: weaken the test")
      write(repo, "test/second_test.exs", "defmodule SecondTest do\nend\n")
      commit(repo, "test: second (ml-x.2)\n\nTests-Committed: ml-x.2")
      write(repo, "specs/notes.md", "notes\n")
      top = commit(repo, "docs: notes")

      assert {_, 1} = run(repo, base, top)

      clone = shallow_clone(repo, 2)
      assert git(clone, ["rev-parse", "--is-shallow-repository"]) == "true"
      assert git(clone, ["cat-file", "-t", base]) == "commit"

      assert {out, 1} = run(clone, base, top)
      assert out =~ "shallow"
    end
  end

  # --- ml-1a7.5 fix round 1 ---------------------------------------------------

  # Path stems that git C-quotes in its plain output (core.quotePath): a non-ASCII
  # byte, a double quote, a backslash, a tab and a newline. Each stem starts with an
  # ASCII marker, so a test can find the path in the output in raw or quoted form.
  @quoted_names [
    {"a non-ASCII name", "nonascii_K3P_é", "nonascii_K3P_"},
    {"a name with a double quote", "quote_Q8D_\"x", "quote_Q8D_"},
    {"a name with a backslash", "backslash_B2S_\\x", "backslash_B2S_"},
    {"a name with a tab", "tab_T5B_\tx", "tab_T5B_"},
    {"a name with a newline", "newline_N4L_\nx", "newline_N4L_"}
  ]

  describe "paths that git quotes (ml-1a7.5.1)" do
    for {label, stem, marker} <- @quoted_names do
      @stem stem
      @marker marker

      test "fails when a later commit without the trailer adds a file under test/ with #{label}",
           %{repo: repo, base: base} do
        path = "test/#{@stem}_test.exs"
        tests_committed(repo)
        write(repo, path, "defmodule QuotedTest do\nend\n")
        bad = commit(repo, "fix: add a quoted test")

        assert {out, 1} = run(repo, base, head(repo))
        assert out =~ @marker
        assert out =~ String.slice(bad, 0, 7)
      end

      test "fails when a later commit without the trailer modifies a file under test/ with #{label}",
           %{repo: repo} do
        path = "test/#{@stem}_test.exs"
        write(repo, path, "defmodule QuotedTest do\nend\n")
        base = commit(repo, "chore: quoted test in BASE")
        tests_committed(repo)
        write(repo, path, "defmodule QuotedTest do\n  # weakened\nend\n")
        bad = commit(repo, "fix: weaken the quoted test")

        assert {out, 1} = run(repo, base, head(repo))
        assert out =~ @marker
        assert out =~ String.slice(bad, 0, 7)
      end

      test "fails when a range with no trailer commit adds a file under test/ with #{label}",
           %{repo: repo, base: base} do
        write(repo, "test/#{@stem}_test.exs", "defmodule QuotedTest do\nend\n")
        commit(repo, "test: quoted")

        assert {out, 1} = run(repo, base, head(repo))
        assert out =~ @marker
      end

      test "fails when a range with no trailer commit changes only a lib/ path with #{label}",
           %{repo: repo, base: base} do
        write(repo, "lib/#{@stem}.ex", "defmodule Quoted do\nend\n")
        commit(repo, "feat: quoted")

        assert {out, 1} = run(repo, base, head(repo))
        assert out =~ "Tests-Committed"
      end

      test "passes with a notice when a range with no trailer commit changes only a docs/ path with #{label}",
           %{repo: repo, base: base} do
        write(repo, "docs/#{@stem}.md", "notes\n")
        commit(repo, "docs: quoted")

        assert {out, 0} = run(repo, base, head(repo))
        assert out =~ "Tests-Committed"
      end

      test "passes when a later commit without the trailer changes only a docs/ path with #{label}",
           %{repo: repo, base: base} do
        tests_committed(repo)
        write(repo, "docs/#{@stem}.md", "notes\n")
        commit(repo, "docs: quoted")

        assert {out, 0} = run(repo, base, head(repo))
        assert out =~ "ok"
      end
    end
  end

  # The trailer key counts only when it is exactly "Tests-Committed" (this case),
  # followed by ": " and the value, as in .claude/hooks/guard.sh. git itself matches
  # the key without case and accepts no space or a space before the colon.
  @inexact_keys [
    {"a lower-case key", "tests-committed: ml-x"},
    {"an upper-case key", "TESTS-COMMITTED: ml-x"},
    {"no space after the colon", "Tests-Committed:ml-x"},
    {"a space before the colon", "Tests-Committed : ml-x"}
  ]

  describe "the trailer key must be exactly \"Tests-Committed: \" (ml-1a7.5.2)" do
    for {label, line} <- @inexact_keys do
      @line line

      test "a trailer line with #{label} does not exempt a commit that modifies a frozen file",
           %{repo: repo, base: base} do
        tests_committed(repo)
        write(repo, @frozen, "defmodule ProbeTest do\n  # weakened\nend\n")
        bad = commit(repo, "fix: weaken the test\n\n" <> @line)

        assert {out, 1} = run(repo, base, head(repo))
        assert out =~ @frozen
        assert out =~ String.slice(bad, 0, 7)
      end

      test "a range whose only trailer line has #{label} is a range with no trailer commit (lib/ fails)",
           %{repo: repo, base: base} do
        write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
        commit(repo, "feat: probe\n\n" <> @line)

        assert {out, 1} = run(repo, base, head(repo))
        assert out =~ "Tests-Committed"
      end

      test "a range whose only trailer line has #{label} is a range with no trailer commit (test/ add fails)",
           %{repo: repo, base: base} do
        write(repo, @frozen, "defmodule ProbeTest do\nend\n")
        commit(repo, "test: probe (ml-x)\n\n" <> @line)

        assert {out, 1} = run(repo, base, head(repo))
        assert out =~ @frozen
      end

      test "a range whose only trailer line has #{label} and changes docs only passes with the notice",
           %{repo: repo, base: base} do
        write(repo, "specs/notes.md", "notes\n")
        commit(repo, "docs: notes\n\n" <> @line)

        assert {out, 0} = run(repo, base, head(repo))
        assert out =~ "notice"
      end
    end

    test "the exact key \"Tests-Committed: \" still counts", %{repo: repo, base: base} do
      write(repo, @frozen, "defmodule ProbeTest do\nend\n")
      commit(repo, "test: probe (ml-x)\n\nTests-Committed: ml-x")
      write(repo, "lib/probe.ex", "defmodule Probe do\nend\n")
      commit(repo, "feat: probe")

      assert {out, 0} = run(repo, base, head(repo))
      assert out =~ "ok"
    end
  end
end
