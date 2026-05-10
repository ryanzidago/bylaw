defmodule Bylaw.Credo.Check.HEEx.RequireImageAltTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireImageAlt
  alias Bylaw.Credo.Plugin.HEExSources

  test "reports missing alt in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/logo.svg">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<img",
      message: "Images must define an alt attribute. Use alt=\"\" for decorative images."
    })
  end

  test "does not report static alt" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/logo.svg" alt="Company logo">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "reports missing alt in single-line H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H"<img src={@src}>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issue(%{line_no: 3, trigger: "<img"})
  end

  test "does not report dynamic alt expression" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src={@src} alt={@alt}>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "does not report when root attrs are present" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img {@attrs}>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "reports self-closing img without alt" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/logo.svg" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issue(%{line_no: 4, trigger: "<img"})
  end

  test "handles multiple img tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/one.svg">
        <img src="/two.svg" alt="Two">
        <img src="/three.svg">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<img"},
      %{line_no: 6, trigger: "<img"}
    ])
  end

  test "does not report dynamic component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.image src="/logo.svg" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "does not report remote component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <Image src="/logo.svg" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
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
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "does not crash when HEEx cannot be tokenized" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/logo.svg"
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "reports missing alt across multiple H sigils" do
    """
    defmodule Example do
      def header(assigns) do
        ~H\"\"\"
        <img src="/header.svg">
        \"\"\"
      end

      def footer(assigns) do
        ~H\"\"\"
        <img src="/footer.svg">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<img"},
      %{line_no: 10, trigger: "<img"}
    ])
  end

  test "reports missing alt in html.heex files" do
    """
    <section>
      <img src="/logo.svg">
      <img src="/decorative.svg" alt="">
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireImageAlt)
    |> assert_issue(%{line_no: 2, trigger: "<img"})
  end

  test "reports missing alt in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("require-image-alt")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    template_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(template_path, """
    <section>
      <img src="/logo.svg">
      <img src="/decorative.svg" alt="">
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
    |> run_check(RequireImageAlt)
    |> assert_issue(%{line_no: 2, trigger: "<img"})
  end

  test "Credo plugin source loader respects excluded html.heex paths" do
    tmp_dir = tmp_dir!("require-image-alt-excluded")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    template_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(template_path, ~s(<img src="/logo.svg">))

    source_files =
      tmp_dir
      |> exec_for_tmp_project(excluded: ["lib/example/"])
      |> HEExSources.LoadSourceFiles.call()
      |> Credo.Execution.get_source_files()

    assert Enum.empty?(source_files)
  end

  defp exec_for_tmp_project(tmp_dir, opts \\ []) do
    excluded = Keyword.get(opts, :excluded, [])

    %{
      Credo.Execution.build()
      | cli_options: %Credo.CLI.Options{path: tmp_dir},
        files: %{included: ["lib/**/*.{ex,exs}"], excluded: excluded}
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
