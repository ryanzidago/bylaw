defmodule Bylaw.Credo.Check.HEEx.PreferNativeInteractiveElementTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.PreferNativeInteractiveElement
  alias Bylaw.Credo.Plugin.HEExSources

  test "reports clickable div in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div phx-click="save">Save</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<div",
      message:
        "Prefer a native interactive element, such as button or a, over a clickable div or span."
    })
  end

  test "reports clickable span in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <span phx-click={JS.push("open")}>Open</span>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> assert_issue(%{line_no: 4, trigger: "<span"})
  end

  test "reports clickable static elements in single-line H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H|<div phx-click="save">Save</div>|
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> assert_issue(%{line_no: 3, trigger: "<div"})
  end

  test "does not report native button or link click handlers" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button" phx-click="save">Save</button>
        <a href={~p"/settings"} phx-click="track">Settings</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> refute_issues()
  end

  test "does not report static elements without click handlers" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="panel">Panel</div>
        <span class="label">Label</span>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> refute_issues()
  end

  test "does not report dynamic root attrs" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div {@attrs} phx-click="save">Save</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> refute_issues()
  end

  test "does not report deliberate accessible widget pattern" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <span role="button" tabindex="0" phx-click="save" phx-keydown="save">Save</span>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> refute_issues()
  end

  test "reports role-only clickable static elements" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div role="button" phx-click="save">Save</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> assert_issue(%{line_no: 4, trigger: "<div"})
  end

  test "does not report components" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.button phx-click="save">Save</.button>
        <Clickable phx-click="save" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> refute_issues()
  end

  test "reports multiple clickable static elements" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div phx-click="one">One</div>
        <button type="button" phx-click="two">Two</button>
        <span phx-click="three">Three</span>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferNativeInteractiveElement)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<div"},
      %{line_no: 6, trigger: "<span"}
    ])
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
    |> run_check(PreferNativeInteractiveElement)
    |> refute_issues()
  end

  test "reports clickable static elements and ignores native alternatives in html.heex files" do
    """
    <section>
      <div phx-click="save">Save</div>
      <button type="button" phx-click="cancel">Cancel</button>
      <a href="/settings" phx-click="track">Settings</a>
      <span phx-click="open">Open</span>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferNativeInteractiveElement)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 2, trigger: "<div"},
      %{line_no: 5, trigger: "<span"}
    ])
  end

  test "reports clickable static elements in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("prefer-native-interactive-element")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    File.mkdir_p!(Path.dirname(template_path))

    File.write!(template_path, """
    <section>
      <div phx-click="save">Save</div>
      <button type="button" phx-click="cancel">Cancel</button>
      <span phx-click="open">Open</span>
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
    |> run_check(PreferNativeInteractiveElement)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 2, trigger: "<div"},
      %{line_no: 4, trigger: "<span"}
    ])
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
