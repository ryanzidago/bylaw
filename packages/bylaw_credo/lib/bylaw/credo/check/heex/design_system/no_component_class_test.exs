defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass
  alias Bylaw.Credo.Plugin.HEExSources

  @message "Give the component a semantic prop such as size, variant, or position instead of a class attribute."

  test "reports a static class attribute on a local component" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.button class="px-4 py-2">Save</.button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClass)
    |> assert_issue(%{
      line_no: 4,
      trigger: "class",
      message: "#{@message} Component: <.button>."
    })
  end

  test "reports a dynamic class expression on a local component" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.spec_text class={[@field_class, "text-xl"]} />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClass)
    |> assert_issue(%{
      line_no: 4,
      trigger: "class",
      message: "#{@message} Component: <.spec_text>."
    })
  end

  test "reports a class attribute on a remote component" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <Layouts.app class="mb-14">Content</Layouts.app>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClass)
    |> assert_issue(%{
      line_no: 4,
      trigger: "class",
      message: "#{@message} Component: <Layouts.app>."
    })
  end

  test "reports the line, column and trigger of the class attribute" do
    """
    <.button class="px-4">Save</.button>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass)
    |> assert_issue(%{line_no: 1, column: 10, trigger: "class"})
  end

  test "reports every component class attribute in a template" do
    """
    <.button class="px-4">Save</.button>
    <div class="px-4">Plain</div>
    <.section class="mb-14">
      <.banner class="mt-9">Archived</.banner>
    </.section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 1, trigger: "class"},
      %{line_no: 3, trigger: "class"},
      %{line_no: 4, trigger: "class"}
    ])
  end

  test "reports a class attribute alongside a root attribute" do
    """
    <.button {@rest} class="px-4">Save</.button>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass)
    |> assert_issue(%{line_no: 1, trigger: "class"})
  end

  test "matches the class attribute regardless of case" do
    """
    <.button CLASS="px-4">Save</.button>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass)
    |> assert_issue(%{line_no: 1, trigger: "CLASS"})
  end

  test "does not report class attributes on plain HTML tags" do
    """
    <div class="px-4">
      <section class={@class}>Content</section>
    </div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass)
    |> refute_issues()
  end

  test "does not report slot attributes" do
    """
    <.table rows={@rows}>
      <:col class="w-8" label="Name">Name</:col>
    </.table>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass)
    |> refute_issues()
  end

  test "does not report other attributes on components" do
    """
    <.spec_text wrapper_class="mb-5" error_class="text-danger" variant="danger" />
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass)
    |> refute_issues()
  end

  test "does not report components listed in excluded_components" do
    """
    <.link class="underline" navigate={~p"/"}>Home</.link>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass, excluded_components: [".link"])
    |> refute_issues()
  end

  test "matches excluded components written with or without a leading dot" do
    """
    <.link class="underline" navigate={~p"/"}>Home</.link>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass, excluded_components: ["link"])
    |> refute_issues()
  end

  test "does not report remote components listed in excluded_components" do
    """
    <Layouts.app class="mb-14">Content</Layouts.app>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass, excluded_components: ["Layouts.app"])
    |> refute_issues()
  end

  test "reports components that are not listed in excluded_components" do
    """
    <.link class="underline" navigate={~p"/"}>Home</.link>
    <.button class="px-4">Save</.button>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass, excluded_components: [".link"])
    |> assert_issue(%{line_no: 2, trigger: "class"})
  end

  test "reports class attributes in html.heex files" do
    """
    <section>
      <.button class="px-4">Save</.button>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoComponentClass)
    |> assert_issue(%{line_no: 2, trigger: "class"})
  end

  test "reports class attributes in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("no-component-class")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    template_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(template_path, """
    <section>
      <.button class="px-4">Save</.button>
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
    |> run_check(NoComponentClass)
    |> assert_issue(%{line_no: 2, trigger: "class"})
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
    |> run_check(NoComponentClass)
    |> refute_issues()
  end

  test "does not crash when HEEx cannot be tokenized" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.button class="px-4"
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClass)
    |> refute_issues()
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
