defmodule Bylaw.Credo.Check.HEEx.RequireLabelForInputTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireLabelForInput

  test "reports unlabelled input in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input id="email" name="email">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLabelForInput)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<input",
      message: "Form controls must have an accessible name."
    })
  end

  test "reports unlabelled select and textarea" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <select id="role"></select>
        <textarea id="bio"></textarea>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLabelForInput)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<select"},
      %{line_no: 5, trigger: "<textarea"}
    ])
  end

  test "does not report controls with explicit labels" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <label for="email">Email</label>
        <input id="email" name="email">

        <label for="role">Role</label>
        <select id="role"></select>

        <label for="bio">Bio</label>
        <textarea id="bio"></textarea>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLabelForInput)
    |> refute_issues()
  end

  test "does not report aria labels" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input aria-label="Search">
        <select aria-labelledby="role-label"></select>
        <textarea aria-label={@label}></textarea>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLabelForInput)
    |> refute_issues()
  end

  test "does not report hidden inputs" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input type="hidden" name="token" value={@token}>
        <input type="HIDDEN" name="return_to" value={@return_to}>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLabelForInput)
    |> refute_issues()
  end

  test "does not report controls with dynamic root attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input {@input_attrs}>
        <select {@select_attrs}></select>
        <textarea {@textarea_attrs}></textarea>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLabelForInput)
    |> refute_issues()
  end

  test "does not report dynamic label relationships" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <label for={@id}>Email</label>
        <input id={@id} name="email">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLabelForInput)
    |> refute_issues()
  end

  test "does not report dynamic input type" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input type={@type} name="email">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLabelForInput)
    |> refute_issues()
  end

  test "reports unlabelled controls in html.heex files" do
    """
    <section>
      <label for="email">Email</label>
      <input id="email" name="email">
      <input id="password" name="password">
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/form.html.heex")
    |> run_check(RequireLabelForInput)
    |> assert_issue(%{line_no: 4, trigger: "<input"})
  end
end
