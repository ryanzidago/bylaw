defmodule Bylaw.Credo.Check.HEEx.NoDuplicateStaticIdsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.NoDuplicateStaticIds
  alias Bylaw.Credo.Plugin.HEExSources

  test "reports duplicate static ids in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <section id="profile">
          <div id="profile"></div>
        </section>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoDuplicateStaticIds)
    |> assert_issue(%{
      line_no: 5,
      trigger: ~s(id="profile"),
      message:
        ~s(Static DOM id values must be unique within a HEEx source. Duplicate id: "profile".)
    })
  end

  test "does not report unique static ids" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <section id="profile">
          <div id="profile-details"></div>
        </section>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoDuplicateStaticIds)
    |> refute_issues()
  end

  test "reports second and later duplicate static ids" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div id="item"></div>
        <span id="item"></span>
        <section id="item"></section>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoDuplicateStaticIds)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 5, trigger: ~s(id="item")},
      %{line_no: 6, trigger: ~s(id="item")}
    ])
  end

  test "does not report dynamic ids or root attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div id={@id}></div>
        <span id={@id}></span>
        <section {@attrs}></section>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoDuplicateStaticIds)
    |> refute_issues()
  end

  test "does not compare dynamic ids against static ids" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div id="profile"></div>
        <span id={"profile"}></span>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoDuplicateStaticIds)
    |> refute_issues()
  end

  test "does not report static id props on components" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.field id="email" />
        <.field id="email" />
        <FormComponent id="account" />
        <FormComponent id="account" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoDuplicateStaticIds)
    |> refute_issues()
  end

  test "does not report duplicate ids across separate H sigils" do
    """
    defmodule Example do
      def header(assigns) do
        ~H\"\"\"
        <header id="page-shell"></header>
        \"\"\"
      end

      def footer(assigns) do
        ~H\"\"\"
        <footer id="page-shell"></footer>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoDuplicateStaticIds)
    |> refute_issues()
  end

  test "reports duplicate static ids in html.heex files" do
    """
    <section id="settings">
      <form id="settings"></form>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoDuplicateStaticIds)
    |> assert_issue(%{line_no: 2, trigger: ~s(id="settings")})
  end

  test "does not report dynamic ids in html.heex files" do
    """
    <section id={@settings_id}>
      <form id={@settings_id}></form>
      <div {@attrs}></div>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoDuplicateStaticIds)
    |> refute_issues()
  end

  test "reports duplicate static ids in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("no-duplicate-static-ids")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    File.mkdir_p!(Path.dirname(template_path))

    File.write!(template_path, """
    <section id="settings">
      <form id="settings"></form>
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
    |> run_check(NoDuplicateStaticIds)
    |> assert_issue(%{line_no: 2, trigger: ~s(id="settings")})
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
    |> run_check(NoDuplicateStaticIds)
    |> refute_issues()
  end

  test "does not crash when HEEx cannot be tokenized" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div id="profile"
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoDuplicateStaticIds)
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
