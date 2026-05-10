defmodule Bylaw.Credo.Check.HEEx.NoElementSpacingTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.NoElementSpacing
  alias Bylaw.Credo.Plugin.HEExSources

  @message "Prefer parent-owned spacing with gap or space utilities instead of margin classes on individual elements."

  test "reports margin utilities in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="mt-4">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> assert_issue(%{
      line_no: 4,
      trigger: "mt-4",
      message: @message
    })
  end

  test "reports multiple margin utilities on the same tag" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="mt-4 mb-2 px-4">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "mt-4"},
      %{line_no: 4, trigger: "mb-2"}
    ])
  end

  test "reports negative margin utilities" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="-mt-4 -mx-2">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "-mt-4"},
      %{line_no: 4, trigger: "-mx-2"}
    ])
  end

  test "reports logical margin utilities" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="ms-4 me-2 -ms-1 rtl:me-3">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> assert_issues(4)
    |> assert_issues_match([
      %{line_no: 4, trigger: "ms-4"},
      %{line_no: 4, trigger: "me-2"},
      %{line_no: 4, trigger: "-ms-1"},
      %{line_no: 4, trigger: "rtl:me-3"}
    ])
  end

  test "reports important margin utilities" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="!mt-4 hover:!mb-2 !-mx-3">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 4, trigger: "!mt-4"},
      %{line_no: 4, trigger: "hover:!mb-2"},
      %{line_no: 4, trigger: "!-mx-3"}
    ])
  end

  test "reports variant-prefixed margin utilities" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="sm:mt-4 hover:mb-2 first:-mt-1 lg:space-y-0">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 4, trigger: "sm:mt-4"},
      %{line_no: 4, trigger: "hover:mb-2"},
      %{line_no: 4, trigger: "first:-mt-1"}
    ])
  end

  test "does not report parent-owned spacing utilities" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="gap-4 space-y-4 space-x-2 lg:space-y-0">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> refute_issues()
  end

  test "does not report padding utilities" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="p-4 px-2 py-3 pt-1 pr-1 pb-1 pl-1">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> refute_issues()
  end

  test "does not report mx-auto" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="mx-auto max-w-screen-lg">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> refute_issues()
  end

  test "does not report dynamic class expressions" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class={@class}>Profile</div>
        <div class={["mt-2", @class]}>Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> refute_issues()
  end

  test "does not report component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.button class="mt-4" />
        <Button class="mb-4" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
    |> refute_issues()
  end

  test "reports margin utilities in html.heex files" do
    """
    <section>
      <div class="mt-4">Profile</div>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementSpacing)
    |> assert_issue(%{line_no: 2, trigger: "mt-4"})
  end

  test "reports margin utilities in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("no-element-spacing")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    template_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(template_path, """
    <section>
      <div class="mt-4">Profile</div>
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
    |> run_check(NoElementSpacing)
    |> assert_issue(%{line_no: 2, trigger: "mt-4"})
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
    |> run_check(NoElementSpacing)
    |> refute_issues()
  end

  test "does not crash when HEEx cannot be tokenized" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="mt-4"
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementSpacing)
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
