defmodule Bylaw.Credo.Check.HEEx.NoRawSVGTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.NoRawSVG
  alias Bylaw.Credo.Plugin.HEExSources

  @message "Avoid raw SVGs. Define SVGs in a separate module or use an SVG library."

  test "reports a raw SVG in an embedded H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <svg viewBox="0 0 16 16"><path d="M1 1" /></svg>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawSVG)
    |> assert_issue(%{line_no: 4, trigger: "<svg", message: @message})
  end

  test "reports each raw SVG with its opening tag location" do
    source_file =
      to_source_file(
        """
        defmodule Example do
          def render(assigns) do
            ~H\"<svg /><svg />\"
          end
        end
        """,
        "lib/example.ex"
      )

    assert [%{line_no: 3, column: 8}, %{line_no: 3, column: 15}] =
             run_check(source_file, NoRawSVG)
  end

  test "reports a raw SVG in a standalone HEEx template" do
    """
    <section>
      <svg
        viewBox="0 0 16 16"
      ><path d="M1 1" /></svg>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoRawSVG)
    |> assert_issue(%{line_no: 2, trigger: "<svg", message: @message})
  end

  test "reports a raw SVG in a template loaded by HEExSources" do
    tmp_dir = tmp_dir!("no-raw-svg")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    template_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(template_path, "<svg viewBox=\"0 0 16 16\" />")

    source_files =
      tmp_dir
      |> exec_for_tmp_project()
      |> HEExSources.LoadSourceFiles.call()
      |> Credo.Execution.get_source_files()

    assert [%Credo.SourceFile{filename: filename, status: :valid}] = source_files
    assert String.ends_with?(filename, "index.html.heex")

    source_files
    |> run_check(NoRawSVG)
    |> assert_issue(%{line_no: 1, trigger: "<svg"})
  end

  test "ignores component calls, comments, and plain strings" do
    """
    defmodule Example do
      def render(assigns) do
        text = "<svg></svg>"
        ~H\"\"\"
        <%!-- <svg /> --%>
        <.icon name="hero-play-solid" />
        <Icons.play />
        <span>&lt;svg&gt;</span>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawSVG)
    |> refute_issues()
  end

  test "ignores source files without HEEx" do
    "defmodule Example do\n  def svg, do: \"<svg />\"\nend\n"
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawSVG)
    |> refute_issues()
  end

  test "permits a dedicated SVG module through a Credo file exclusion" do
    tmp_dir = tmp_dir!("no-raw-svg-exclusion")
    icons_path = Path.join([tmp_dir, "lib", "example_web", "icons.ex"])
    page_path = Path.join([tmp_dir, "lib", "example_web", "page.ex"])

    icons_path
    |> Path.dirname()
    |> File.mkdir_p!()

    for path <- [icons_path, page_path] do
      File.write!(path, "defmodule Example do\n  def render(assigns), do: ~H\"<svg />\"\nend\n")
    end

    tmp_dir
    |> Path.join(".credo.exs")
    |> File.write!("""
    %{
      configs: [
        %{
          name: "default",
          files: %{included: ["lib/"], excluded: []},
          checks: %{
            extra: [
              {Bylaw.Credo.Check.HEEx.NoRawSVG,
               [files: %{excluded: [~r{/icons\\.ex$}]}]}
            ]
          }
        }
      ]
    }
    """)

    exec =
      Credo.run([
        "--working-dir",
        tmp_dir,
        "--config-file",
        Path.join(tmp_dir, ".credo.exs"),
        "--strict"
      ])

    issues =
      exec
      |> Credo.Execution.get_issues()
      |> Enum.filter(&(&1.check == NoRawSVG))

    assert [%Credo.Issue{filename: filename, trigger: "<svg"}] = issues
    assert String.ends_with?(filename, "page.ex")
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

    File.mkdir_p!(path)
    path
  end
end
