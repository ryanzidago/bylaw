defmodule Bylaw.Credo.Check.NoRepoInController do
  @moduledoc """
  Disallows calling `Repo` directly from controller modules.

  Controllers should delegate data access to context modules (e.g. `Conversations`,
  `Runs`) rather than calling `Repo` directly. This enforces a boundary between the
  web layer and the persistence layer.

  ## Examples

  Bad:

      defmodule MyAppWeb.ThingController do
        def show(conn, %{"id" => id}) do
          thing = Repo.get!(Thing, id)
          render(conn, :show, thing: thing)
        end
      end

  Good:

      defmodule MyAppWeb.ThingController do
        def show(conn, %{"id" => id}) do
          thing = Things.get_thing!(id)
          render(conn, :show, thing: thing)
        end
      end
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: """
      Controllers should not call `Repo` directly. Use a context module instead.

      Direct `Repo` calls in controllers bypass the context boundary and make it
      harder to test, reuse, and reason about data access.
      """
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    if controller_file?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp controller_file?(filename) do
    String.contains?(filename, "_controller.ex") and
      not String.ends_with?(filename, "_test.exs")
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, aliases}, _func]}, meta, _args} = ast,
         issues,
         issue_meta
       ) do
    if List.last(aliases) == :Repo do
      {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message: "Do not call `Repo` from a controller. Use a context module instead.",
      trigger: "Repo",
      line_no: line_no
    )
  end
end
