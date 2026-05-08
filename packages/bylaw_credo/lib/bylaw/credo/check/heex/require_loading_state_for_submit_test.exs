defmodule Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmitTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmit

  test "reports submit button without loading state" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="submit">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<button",
      message: "Submit actions must expose a loading or disabled state."
    })
  end

  test "does not report submit button with phx-disable-with" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="submit" phx-disable-with="Saving...">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> refute_issues()
  end

  test "does not report disabled submit button" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="submit" disabled>Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> refute_issues()
  end

  test "reports submit input without loading state" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <input type="submit" value="Save" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> assert_issue(%{line_no: 4, trigger: "<input"})
  end

  test "does not report non-submit buttons" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button" phx-click="close">Close</button>
        <button type={@type}>Continue</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> refute_issues()
  end

  test "does not report when root attrs are present" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button {@attrs} type="submit">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> refute_issues()
  end

  test "reports phx-submit form without a submit control or loading state" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save">
          <input name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> assert_issue(%{line_no: 4, trigger: "<.form"})
  end

  test "reports native phx-submit form without a submit control or loading state" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <form phx-submit="save">
          <input name="name" />
        </form>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> assert_issue(%{line_no: 4, trigger: "<form"})
  end

  test "does not report phx-submit form with phx-disable-with" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save" phx-disable-with="Saving...">
          <input name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> refute_issues()
  end

  test "does not report phx-submit form with root attrs" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.form {@attrs} for={@form} phx-submit="save">
          <input name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> refute_issues()
  end

  test "does not duplicate form issue when submit button is reported" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save">
          <button type="submit">Save</button>
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> assert_issue(%{line_no: 5, trigger: "<button"})
  end

  test "does not report phx-submit form with loading submit button" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save">
          <button type="submit" phx-disable-with="Saving...">Save</button>
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit)
    |> refute_issues()
  end

  test "does not report phx-submit form with configured loading attribute" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save" data-loading>
          <input name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit, loading_attrs: ["data-loading"])
    |> refute_issues()
  end

  test "does not report submit button with configured loading attribute" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="submit" data-loading>Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit, loading_attrs: ["data-loading"])
    |> refute_issues()
  end

  test "does not report configured loading class pattern" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="submit" class="phx-submit-loading:opacity-60">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit, loading_class_patterns: ["phx-submit-loading:"])
    |> refute_issues()
  end

  test "does not report phx-submit form with configured loading class pattern" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save" class="phx-submit-loading:opacity-60">
          <input name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLoadingStateForSubmit, loading_class_patterns: ["phx-submit-loading:"])
    |> refute_issues()
  end

  test "reports missing loading state in html.heex files" do
    """
    <form phx-submit="save">
      <button type="submit">Save</button>
    </form>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireLoadingStateForSubmit)
    |> assert_issue(%{line_no: 2, trigger: "<button"})
  end
end
