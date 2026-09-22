defmodule Bylaw.Credo.Check.HEEx.RequireFormFieldIdOrNameTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireFormFieldIdOrName

  test "reports input without id or name" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input aria-label="Search">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFormFieldIdOrName)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<input",
      message: "Form controls must have an id or a name."
    })
  end

  test "reports textarea and select without id or name" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <textarea readonly aria-hidden="true" placeholder="Description"></textarea>
        <select aria-label="Role"></select>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFormFieldIdOrName)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<textarea"},
      %{line_no: 5, trigger: "<select"}
    ])
  end

  test "does not report controls with only an id or only a name" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input id="search" aria-label="Search">
        <textarea name="description"></textarea>
        <select id="role"></select>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFormFieldIdOrName)
    |> refute_issues()
  end

  test "does not report dynamic ids or names" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input id={@id}>
        <textarea name={@form[:body].name}></textarea>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFormFieldIdOrName)
    |> refute_issues()
  end

  test "does not report controls with dynamic root attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input {@rest}>
        <select {@rest}></select>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFormFieldIdOrName)
    |> refute_issues()
  end

  test "does not report hidden, submit, button, reset, image or dynamic-type inputs" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input type="hidden" value={@token}>
        <input type="submit" value="Save">
        <input type="BUTTON" value="Cancel">
        <input type="reset">
        <input type="image" src="/go.png" alt="Go">
        <input type={@type}>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFormFieldIdOrName)
    |> refute_issues()
  end

  test "reports text inputs with an explicit type" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input type="email" aria-label="Email">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFormFieldIdOrName)
    |> assert_issue(%{line_no: 4, trigger: "<input"})
  end

  test "does not report components" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.input type="text" />
        <MyApp.Components.textarea />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFormFieldIdOrName)
    |> refute_issues()
  end

  test "reports controls without id or name in html.heex files" do
    """
    <section>
      <input id="email" name="email">
      <textarea aria-label="Notes"></textarea>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/form.html.heex")
    |> run_check(RequireFormFieldIdOrName)
    |> assert_issue(%{line_no: 3, trigger: "<textarea"})
  end
end
