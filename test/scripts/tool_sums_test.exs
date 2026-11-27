defmodule MqttLens.ToolSumsScriptTest do
  # Contract of scripts/ci/tool-sums.sh (ml-1a7.4):
  #   scripts/ci/tool-sums.sh [ROOT]   (default: the repository root)
  # It reads ROOT/config/config.exs, ROOT/config/tool-sums.txt and the binaries in
  # ROOT/_build/ with the names that `mix assets.setup` gives them. It never runs them.
  # tool-sums.txt format:
  #   # <comment, for example the source URL>
  #   version <tool> <version>
  #   <sha256>  <tool>-<target>
  # Exit 0 = pass, exit 1 = fail.
  use ExUnit.Case, async: true

  @script Path.expand("../../scripts/ci/tool-sums.sh", __DIR__)
  @root Path.expand("../..", __DIR__)

  @tailwind "4.3.3"
  @esbuild "0.25.4"

  setup do
    root = Path.join(System.tmp_dir!(), "tool-sums-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "config"))
    File.mkdir_p!(Path.join(root, "_build"))
    on_exit(fn -> File.rm_rf!(root) end)

    marker = Path.join(root, "binary-was-run")
    tailwind_body = binary(marker, "tailwind")
    esbuild_body = binary(marker, "esbuild")
    write_binary(root, tailwind_bin(@tailwind), tailwind_body)
    write_binary(root, esbuild_bin(), esbuild_body)
    write_config(root, @tailwind, @esbuild)

    sums = [
      "# tailwind source: https://example.invalid/tailwind/sha256sums.txt",
      "# esbuild source: https://example.invalid/esbuild",
      "version tailwind #{@tailwind}",
      "version esbuild #{@esbuild}",
      "#{sha256(tailwind_body)}  #{tailwind_key(@tailwind)}",
      "#{sha256(esbuild_body)}  #{esbuild_key()}"
    ]

    write_sums(root, sums)

    {:ok,
     root: root,
     marker: marker,
     sums: sums,
     tailwind_body: tailwind_body,
     esbuild_body: esbuild_body}
  end

  # The binary names and targets come from the Elixir installers, so the script must
  # check the same files that `mix assets.setup` writes.
  defp tailwind_bin(version), do: Path.basename(Tailwind.bin_path(version))
  defp esbuild_bin, do: Path.basename(Esbuild.bin_path())
  defp tailwind_key(version), do: String.replace_suffix(tailwind_bin(version), "-#{version}", "")
  defp esbuild_key, do: esbuild_bin()

  defp binary(marker, name),
    do: "#!/bin/sh\n# #{name} probe #{System.unique_integer()}\ntouch '#{marker}'\n"

  defp write_binary(root, name, body) do
    path = Path.join([root, "_build", name])
    File.write!(path, body)
    File.chmod!(path, 0o755)
  end

  defp write_config(root, tailwind, esbuild) do
    File.write!(Path.join([root, "config", "config.exs"]), """
    import Config

    # Configure esbuild (the version is required)
    config :esbuild,
      version: "#{esbuild}",
      mqtt_lens: [
        args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
        cd: Path.expand("../assets", __DIR__)
      ]

    # Configure tailwind (the version is required)
    config :tailwind,
      version: "#{tailwind}",
      mqtt_lens: [
        args: ~w(--input=assets/css/app.css --output=priv/static/assets/css/app.css),
        cd: Path.expand("..", __DIR__)
      ]
    """)
  end

  defp write_sums(root, lines),
    do: File.write!(Path.join([root, "config", "tool-sums.txt"]), Enum.join(lines, "\n") <> "\n")

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp run(args), do: System.cmd(@script, args, stderr_to_stdout: true)

  defp without(lines, needle), do: Enum.reject(lines, &String.contains?(&1, needle))

  defp recipe(target) do
    @root
    |> Path.join("Makefile")
    |> File.read!()
    |> String.split("\n")
    |> Enum.drop_while(&(not String.starts_with?(&1, target <> ":")))
    |> Enum.drop(1)
    |> Enum.take_while(&String.starts_with?(&1, "\t"))
    |> Enum.map(&String.trim/1)
  end

  defp index_of(lines, needle) do
    Enum.find_index(lines, &String.contains?(&1, needle)) ||
      flunk("#{needle} is not in the recipe")
  end

  test "passes when both binaries match and does not run them",
       %{root: root, marker: marker} do
    assert {_, 0} = run([root])
    refute File.exists?(marker)
  end

  describe "mismatch" do
    test "fails when the tailwind binary does not match", %{root: root} do
      write_binary(root, tailwind_bin(@tailwind), "#!/bin/sh\n# tampered\n")
      assert {out, 1} = run([root])
      assert out =~ "tailwind"
    end

    test "fails when the esbuild binary does not match", %{root: root} do
      write_binary(root, esbuild_bin(), "#!/bin/sh\n# tampered\n")
      assert {out, 1} = run([root])
      assert out =~ "esbuild"
    end

    test "does not run a mismatched binary", %{root: root, marker: marker} do
      write_binary(root, tailwind_bin(@tailwind), "#!/bin/sh\ntouch '#{marker}'\n")
      assert {_, 1} = run([root])
      refute File.exists?(marker)
    end
  end

  describe "missing binary" do
    test "fails when the tailwind binary is missing", %{root: root} do
      File.rm!(Path.join([root, "_build", tailwind_bin(@tailwind)]))
      assert {out, 1} = run([root])
      assert out =~ "tailwind"
    end

    test "fails when the esbuild binary is missing", %{root: root} do
      File.rm!(Path.join([root, "_build", esbuild_bin()]))
      assert {out, 1} = run([root])
      assert out =~ "esbuild"
    end
  end

  describe "missing sum line for the current target" do
    test "fails when there is no tailwind line for the target", %{root: root, sums: sums} do
      other = "#{String.duplicate("0", 64)}  tailwind-plan9-x64"
      write_sums(root, without(sums, "  #{tailwind_key(@tailwind)}") ++ [other])
      assert {out, 1} = run([root])
      assert out =~ "tailwind"
    end

    test "fails when there is no esbuild line for the target", %{root: root, sums: sums} do
      other = "#{String.duplicate("0", 64)}  esbuild-plan9-x64"
      write_sums(root, without(sums, "  #{esbuild_key()}") ++ [other])
      assert {out, 1} = run([root])
      assert out =~ "esbuild"
    end

    test "fails when the correct sum is only in a comment line",
         %{root: root, sums: sums, tailwind_body: body} do
      comment = "# #{sha256(body)}  #{tailwind_key(@tailwind)}"
      write_sums(root, without(sums, "  #{tailwind_key(@tailwind)}") ++ [comment])
      assert {_, 1} = run([root])
    end

    test "fails when the correct sum is only under a longer name",
         %{root: root, sums: sums, tailwind_body: body} do
      longer = "#{sha256(body)}  #{tailwind_key(@tailwind)}-old"
      write_sums(root, without(sums, "  #{tailwind_key(@tailwind)}") ++ [longer])
      assert {_, 1} = run([root])
    end
  end

  describe "version" do
    test "fails when the tailwind version in config.exs differs from tool-sums.txt",
         %{root: root, tailwind_body: body} do
      # The binary is there under both names with the correct sum, so only the
      # version check can fail.
      write_binary(root, tailwind_bin("4.9.9"), body)
      write_config(root, "4.9.9", @esbuild)
      assert {out, 1} = run([root])
      assert out =~ "tailwind"
    end

    test "fails when the esbuild version in config.exs differs from tool-sums.txt",
         %{root: root} do
      write_config(root, @tailwind, "0.99.0")
      assert {out, 1} = run([root])
      assert out =~ "esbuild"
    end

    test "fails when tool-sums.txt has no tailwind version line", %{root: root, sums: sums} do
      write_sums(root, without(sums, "version tailwind"))
      assert {_, 1} = run([root])
    end

    test "fails when tool-sums.txt has no esbuild version line", %{root: root, sums: sums} do
      write_sums(root, without(sums, "version esbuild"))
      assert {_, 1} = run([root])
    end
  end

  describe "fail closed" do
    test "fails when tool-sums.txt is missing", %{root: root} do
      File.rm!(Path.join([root, "config", "tool-sums.txt"]))
      assert {_, 1} = run([root])
    end

    test "fails when config.exs is missing", %{root: root} do
      File.rm!(Path.join([root, "config", "config.exs"]))
      assert {_, 1} = run([root])
    end

    test "fails when the root does not exist", %{root: root} do
      assert {_, 1} = run([Path.join(root, "no-such-dir")])
    end

    test "fails when a sum is not a 64-character hex string", %{root: root, sums: sums} do
      bad = "abc123  #{tailwind_key(@tailwind)}"
      write_sums(root, without(sums, "  #{tailwind_key(@tailwind)}") ++ [bad])
      assert {_, 1} = run([root])
    end

    test "fails when two lines for the same target disagree",
         %{root: root, sums: sums} do
      conflict = "#{String.duplicate("f", 64)}  #{tailwind_key(@tailwind)}"
      write_sums(root, sums ++ [conflict])
      assert {_, 1} = run([root])
    end

    test "fails when the binary is a directory", %{root: root} do
      path = Path.join([root, "_build", esbuild_bin()])
      File.rm!(path)
      File.mkdir_p!(path)
      assert {_, 1} = run([root])
    end
  end

  describe "committed config/tool-sums.txt" do
    setup do
      {:ok,
       lines: @root |> Path.join("config/tool-sums.txt") |> File.read!() |> String.split("\n")}
    end

    test "has the versions of config/config.exs", %{lines: lines} do
      assert "version tailwind #{Application.fetch_env!(:tailwind, :version)}" in lines
      assert "version esbuild #{Application.fetch_env!(:esbuild, :version)}" in lines
    end

    test "has a sha256 line for linux-x64 for each tool", %{lines: lines} do
      for name <- ["tailwind-linux-x64", "esbuild-linux-x64"] do
        assert Enum.any?(lines, &Regex.match?(~r/\A[0-9a-f]{64}  #{name}\z/, &1)),
               "no sha256 line for #{name}"
      end
    end

    test "records the upstream source URLs in comment lines", %{lines: lines} do
      comments = Enum.filter(lines, &String.starts_with?(&1, "#"))
      assert Enum.any?(comments, &(&1 =~ "https://github.com/tailwindlabs/tailwindcss/releases"))
      assert Enum.any?(comments, &(&1 =~ "https://registry.npmjs.org/@esbuild/"))
    end
  end

  describe "order in make setup, make check and CI" do
    test "make setup checks the sums after assets.setup and before assets.build" do
      lines = recipe("setup")
      deps = index_of(lines, "mix deps.get")
      setup = index_of(lines, "mix assets.setup")
      sums = index_of(lines, "scripts/ci/tool-sums.sh")
      build = index_of(lines, "mix assets.build")
      assert deps < setup and setup < sums and sums < build
    end

    test "make check runs tool-sums.sh" do
      assert Enum.any?(recipe("check"), &String.contains?(&1, "scripts/ci/tool-sums.sh"))
    end

    test "CI checks the sums before the first run of the binaries" do
      ci = File.read!(Path.join(@root, ".github/workflows/ci.yml"))

      check =
        [:binary.match(ci, "make setup"), :binary.match(ci, "scripts/ci/tool-sums.sh")]
        |> Enum.reject(&(&1 == :nomatch))
        |> Enum.map(&elem(&1, 0))
        |> Enum.min(fn -> flunk("CI does not run make setup or tool-sums.sh") end)

      first_run =
        ["assets.build", "assets.deploy", "mix tailwind", "mix esbuild"]
        |> Enum.map(&:binary.match(ci, &1))
        |> Enum.reject(&(&1 == :nomatch))
        |> Enum.map(&elem(&1, 0))

      for pos <- first_run, do: assert(check < pos)
    end
  end
end
