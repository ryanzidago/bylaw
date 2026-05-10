defmodule Bylaw.Credo.Check.HEEx.NoJavascriptHrefTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.NoJavascriptHref
  alias Bylaw.Credo.Plugin.HEExSources

  @message "Links must not use javascript: href values."

  test "reports javascript href in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="javascript:alert('x')">Delete</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoJavascriptHref)
    |> assert_issue(%{
      line_no: 4,
      trigger: "href",
      message: @message
    })
  end

  test "reports mixed-case javascript href with leading whitespace" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="  JaVaScRiPt:alert('x')">Delete</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoJavascriptHref)
    |> assert_issue(%{line_no: 4, trigger: "href"})
  end

  test "reports single-quoted javascript href" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href='javascript:alert("x")'>Delete</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoJavascriptHref)
    |> assert_issue(%{line_no: 4, trigger: "href"})
  end

  test "reports case-insensitive href attribute names" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a HREF="javascript:alert('x')">Delete</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoJavascriptHref)
    |> assert_issue(%{line_no: 4, trigger: "HREF"})
  end

  test "does not report non-javascript hrefs" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/account">Account</a>
        <a href="https://example.com">Example</a>
        <a href="mailto:support@example.com">Support</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoJavascriptHref)
    |> refute_issues()
  end

  test "does not report dynamic href expressions" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href={@href}>Dynamic</a>
        <a href={~p"/account"}>Account</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoJavascriptHref)
    |> refute_issues()
  end

  test "does not report dynamic root attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a {@attrs}>Dynamic attributes</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoJavascriptHref)
    |> refute_issues()
  end

  test "reports javascript href in html.heex files" do
    """
    <section>
      <a href="/account">Account</a>
      <a href="javascript:alert('x')">Delete</a>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoJavascriptHref)
    |> assert_issue(%{line_no: 3, trigger: "href"})
  end

  test "reports javascript href in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("no-javascript-href")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    template_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(template_path, """
    <section>
      <a href="javascript:alert('x')">Delete</a>
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
    |> run_check(NoJavascriptHref)
    |> assert_issue(%{line_no: 2, trigger: "href"})
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
