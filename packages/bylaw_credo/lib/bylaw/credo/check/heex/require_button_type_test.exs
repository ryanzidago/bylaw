defmodule Bylaw.Credo.Check.HEEx.RequireButtonTypeTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireButtonType
  alias Bylaw.Credo.Plugin.HEExSources

  test "reports missing type in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button>Open menu</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<button",
      message: "Buttons must define an explicit type attribute."
    })
  end

  test "does not report static type" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button">Open menu</button>
        <button type="submit">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> refute_issues()
  end

  test "does not report dynamic type expression" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type={@type}>Continue</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> refute_issues()
  end

  test "does not report when root attrs are present" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button {@attrs}>Continue</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> refute_issues()
  end

  test "reports self-closing button without type" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button phx-click="close" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> assert_issue(%{line_no: 4, trigger: "<button"})
  end

  test "reports missing type in single-line H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H"<button>Close</button>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> assert_issue(%{line_no: 3, trigger: "<button"})
  end

  test "handles multiple button tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button>Cancel</button>
        <button type="submit">Save</button>
        <button phx-click="copy">Copy</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<button"},
      %{line_no: 6, trigger: "<button"}
    ])
  end

  test "does not report component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.button>Save</.button>
        <Button>Save</Button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> refute_issues()
  end

  test "does not crash when source has no HEEx" do
    """
    defmodule Example do
      def render(assigns) do
        "not a template"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> refute_issues()
  end

  test "does not crash when HEEx cannot be tokenized" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button phx-click="close"
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireButtonType)
    |> refute_issues()
  end

  test "reports missing type in html.heex files" do
    """
    <form>
      <button>Save</button>
      <button type="button">Cancel</button>
    </form>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireButtonType)
    |> assert_issue(%{line_no: 2, trigger: "<button"})
  end

  test "does not report explicit or dynamic type in html.heex files" do
    """
    <form>
      <button type="button">Cancel</button>
      <button type={@type}>Save</button>
      <button {@attrs}>Continue</button>
    </form>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireButtonType)
    |> refute_issues()
  end

  test "reports missing type in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("require-button-type")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    File.mkdir_p!(Path.dirname(template_path))

    File.write!(template_path, """
    <form>
      <button>Save</button>
      <button type="button">Cancel</button>
    </form>
    """)

    source_files =
      tmp_dir
      |> exec_for_tmp_project()
      |> HEExSources.LoadSourceFiles.call()
      |> Credo.Execution.get_source_files()

    assert [%Credo.SourceFile{filename: filename, status: :valid}] = source_files
    assert String.ends_with?(filename, "index.html.heex")

    source_files
    |> run_check(RequireButtonType)
    |> assert_issue(%{line_no: 2, trigger: "<button"})
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
