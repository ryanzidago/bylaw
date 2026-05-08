defmodule Bylaw.Credo.Check.HEEx.RequireTargetBlankRelTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireTargetBlankRel
  alias Bylaw.Credo.Plugin.HEExSources

  test "reports missing rel on static target blank link in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a target="_blank" href="https://example.com">Example</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<a",
      message: ~s(Links with target="_blank" must define rel with noopener.)
    })
  end

  test "reports static rel without noopener" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a target="_blank" rel="external noreferrer" href="https://example.com">Example</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> assert_issue(%{line_no: 4, trigger: "<a"})
  end

  test "reports target blank regardless of attribute order" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="https://example.com" rel="external" target="_blank">Example</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> assert_issue(%{line_no: 4, trigger: "<a"})
  end

  test "does not report static rel with noopener" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a target="_blank" rel="noopener" href="https://example.com">Example</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> refute_issues()
  end

  test "does not report noopener among multiple rel values in any order" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a target="_blank" rel="external noreferrer noopener" href="https://one.example">One</a>
        <a target="_blank" rel="noopener external noreferrer" href="https://two.example">Two</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> refute_issues()
  end

  test "matches target and rel tokens case-insensitively" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a target="_Blank" rel="external" href="https://unsafe.example">Unsafe</a>
        <a target="_BLANK" rel="NoOpener" href="https://safe.example">Safe</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> assert_issue(%{line_no: 4, trigger: "<a"})
  end

  test "matches rel tokens separated by repeated whitespace" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a target="_blank" rel="external  noopener   noreferrer" href="https://example.com">Example</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> refute_issues()
  end

  test "does not report links without static target blank" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/same-page">Internal</a>
        <a target="_self" href="/same-page">Same page</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> refute_issues()
  end

  test "does not report dynamic target or rel values" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a target={@target} rel="external" href="https://example.com">Dynamic target</a>
        <a target="_blank" rel={@rel} href="https://example.com">Dynamic rel</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> refute_issues()
  end

  test "does not report when root attrs are present" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a target="_blank" href="https://example.com" {@attrs}>Example</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> refute_issues()
  end

  test "does not report component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.link target="_blank" href="https://example.com">Example</.link>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireTargetBlankRel)
    |> refute_issues()
  end

  test "reports missing rel in html.heex files" do
    """
    <section>
      <a target="_blank" href="https://example.com">Example</a>
      <a target="_blank" rel="noreferrer noopener" href="https://safe.example">Safe</a>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireTargetBlankRel)
    |> assert_issue(%{line_no: 2, trigger: "<a"})
  end

  test "reports missing rel in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("require-target-blank-rel")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    File.mkdir_p!(Path.dirname(template_path))

    File.write!(template_path, """
    <section>
      <a href="https://example.com" target="_blank">Example</a>
      <a href="https://safe.example" target="_blank" rel="noopener">Safe</a>
    </section>
    """)

    source_files =
      tmp_dir
      |> exec_for_tmp_project()
      |> HEExSources.LoadSourceFiles.call()
      |> Credo.Execution.get_source_files()

    assert [%Credo.SourceFile{filename: filename, status: :valid}] = source_files
    assert String.ends_with?(filename, "index.html.heex")

    source_files
    |> run_check(RequireTargetBlankRel)
    |> assert_issue(%{line_no: 2, trigger: "<a"})
  end

  defp exec_for_tmp_project(tmp_dir) do
    %{
      Credo.Execution.build()
      | cli_options: %Credo.CLI.Options{path: tmp_dir},
        files: %{included: ["lib/**/*.{ex,exs}"], excluded: []}
    }
  end

  defp tmp_dir!(name) do
    path =
      Path.join(System.tmp_dir!(), "bylaw-credo-#{name}-#{System.unique_integer([:positive])}")

    File.rm_rf!(path)
    File.mkdir_p!(path)

    path
  end
end
