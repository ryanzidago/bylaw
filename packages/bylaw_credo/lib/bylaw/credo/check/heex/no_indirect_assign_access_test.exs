defmodule Bylaw.Credo.Check.HEEx.NoIndirectAssignAccessTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.NoIndirectAssignAccess

  test "reports Map.get access to assigns in an embedded HEEx expression" do
    """
    defmodule Example do
      def render(assigns) do
        ~H"<h1>{Map.get(assigns, :title)}</h1>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> assert_issue(%{trigger: "{Map.get(assigns, :title)", line_no: 3})
  end

  test "reports bracket access to assigns in an embedded HEEx expression" do
    """
    defmodule Example do
      def render(assigns) do
        ~H"<h1>{assigns[:title]}</h1>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> assert_issue(%{trigger: "{assigns[:title]", line_no: 3})
  end

  test "reports indirect access in HEEx attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H"<.heading title={Map.get(assigns, :title)} id={assigns[:id]} />"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> assert_issues(2)
  end

  test "reports Map.get access with an explicit fallback" do
    """
    defmodule Example do
      def render(assigns) do
        ~H'<h1>{Map.get(assigns, :title, "Default")}</h1>'
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> assert_issue(%{trigger: "{Map.get(assigns, :title, \"Default\")"})
  end

  test "reports multiple indirect assign accesses" do
    """
    defmodule Example do
      def render(assigns) do
        ~H"<p>{Map.get(assigns, :title)} {assigns[:summary]}</p>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> assert_issues(2)
  end

  test "reports indirect access in standalone HEEx" do
    "<h1>{Map.get(assigns, :title)}</h1>"
    |> Credo.SourceFile.parse("lib/example.html.heex")
    |> run_check(NoIndirectAssignAccess)
    |> assert_issue(%{trigger: "{Map.get(assigns, :title)", line_no: 1})
  end

  test "does not report direct assign access" do
    """
    defmodule Example do
      def render(assigns), do: ~H"<h1>{@title}</h1>"
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> refute_issues()
  end

  test "does not report access on an ordinary map" do
    """
    defmodule Example do
      def render(assigns) do
        values = %{title: "Title"}
        ~H"<h1>{Map.get(values, :title)} {values[:title]}</h1>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> refute_issues()
  end

  test "does not report dynamic assign keys" do
    """
    defmodule Example do
      def render(assigns) do
        key = :title
        ~H"<h1>{Map.get(assigns, key)} {assigns[key]}</h1>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> refute_issues()
  end

  test "does not report matching Elixir code outside HEEx" do
    """
    defmodule Example do
      def title(assigns), do: Map.get(assigns, :title)
      def summary(assigns), do: assigns[:summary]
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> refute_issues()
  end

  test "does not crash on invalid HEEx expressions" do
    """
    defmodule Example do
      def render(assigns), do: ~H"<h1>{Map.get(assigns, }</h1>"
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoIndirectAssignAccess)
    |> refute_issues()
  end
end
