defmodule Bylaw.Credo.Check.Phoenix.NoRepoInController do
  @moduledoc """
  Disallows calling `Repo` directly from controller modules.

  ## Examples

  Controllers should delegate data access to context modules (e.g. `Conversations`,
  `Runs`) rather than calling `Repo` directly. This enforces a boundary between the
  web layer and the persistence layer.
  Avoid:

        defmodule MyAppWeb.ThingController do
          def show(conn, %{"id" => id}) do
            thing = Repo.get!(Thing, id)
            render(conn, :show, thing: thing)
          end
        end

  Prefer:

        defmodule MyAppWeb.ThingController do
          def show(conn, %{"id" => id}) do
            thing = Things.get_thing!(id)
            render(conn, :show, thing: thing)
          end
        end


  Keeping persistence access in contexts gives controllers a thin web boundary
  and centralizes authorization, query composition, and domain policy. Direct
  Repo calls make those rules easy to bypass and duplicate across endpoints.
  ## Options

  This check has no check-specific options. Configure it with an empty option list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Phoenix.NoRepoInController, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :design,
    tags: [:web, :architecture],
    explanations: [check: @moduledoc]

  @doc false
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
