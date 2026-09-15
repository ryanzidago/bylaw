defmodule Bylaw.Credo.Check.Testing.RequireAsyncTests do
  @moduledoc """
  Require test cases to run with `async: true`, or to explain why they cannot.

  ## Examples

  Avoid:

      defmodule ExampleTest do
        use ExUnit.Case, async: false

        test "example" do
          assert true
        end
      end

  Prefer:

      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "example" do
          assert true
        end
      end

  Or, when the case genuinely cannot run concurrently:

      defmodule ExampleTest do
        # async: false because these tests share the global application environment
        use ExUnit.Case, async: false

        test "example" do
          assert true
        end
      end


  Async test cases run concurrently, which shortens suite time and surfaces
  accidental coupling to shared state. Forcing `async: true` by default makes
  the slower, riskier `async: false` an explicit, reviewed decision.

  The explanation is a comment on the `use` line itself or a contiguous
  comment block on the line(s) directly above it; a blank line breaks the
  association. Aliased case modules (for example `alias ExUnit.Case, as: EC`)
  are not tracked.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.RequireAsyncTests,
           [
             case_modules: [MyApp.DataCase, MyApp.ConnCase]
           ]}
        ]
      }
    ]
  }
  ```

  - `:case_modules` - Additional case modules (beyond `ExUnit.Case` and
    `ExUnit.CaseTemplate`) whose `use` options should be checked, such as
    app-specific case templates like `MyApp.DataCase`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.RequireAsyncTests, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :consistency,
    tags: [:testing],
    param_defaults: [case_modules: []],
    explanations: [
      check: @moduledoc,
      params: [
        case_modules: """
        Additional case modules (beyond `ExUnit.Case` and `ExUnit.CaseTemplate`)
        whose `use` options should be checked.
        """
      ]
    ]

  @default_case_modules [ExUnit.Case, ExUnit.CaseTemplate]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    case_modules = case_modules(params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, case_modules, source_file))
  end

  defp traverse(
         {:use, meta, [module, options]} = ast,
         issues,
         issue_meta,
         case_modules,
         source_file
       )
       when is_list(options) do
    if tracked_case?(module, case_modules) and not async_true?(options) do
      trigger = trigger(module, options)
      line_no = meta[:line] || 0

      if explained_by_comment?(source_file, line_no) do
        {ast, issues}
      else
        {ast, [issue_for(issue_meta, trigger, line_no) | issues]}
      end
    else
      {ast, issues}
    end
  end

  defp traverse({:use, meta, [module]}, issues, issue_meta, case_modules, source_file) do
    traverse({:use, meta, [module, []]}, issues, issue_meta, case_modules, source_file)
  end

  defp traverse(ast, issues, _issue_meta, _case_modules, _source_file), do: {ast, issues}

  defp case_modules(params) do
    extra = Params.get(params, :case_modules, __MODULE__)

    Enum.map(@default_case_modules ++ extra, &Module.split/1)
  end

  defp tracked_case?({:__aliases__, _meta, module_parts}, case_modules) do
    parts = Enum.map(module_parts, &to_string/1)
    parts in case_modules
  end

  defp tracked_case?(_module, _case_modules), do: false

  defp async_true?(options) do
    case Keyword.fetch(options, :async) do
      # Only the literal `false` is known to be non-async; any other value
      # (including non-literal expressions) cannot be verified statically.
      {:ok, false} -> false
      {:ok, _value} -> true
      :error -> false
    end
  end

  defp trigger(module, options) do
    if Keyword.has_key?(options, :async) do
      "async: false"
    else
      "use " <> Macro.to_string(module)
    end
  end

  defp explained_by_comment?(source_file, line_no) do
    line_map =
      source_file
      |> Credo.SourceFile.lines()
      |> Map.new()

    trailing_comment?(Map.get(line_map, line_no, "")) or comment_block_above?(line_map, line_no)
  end

  defp trailing_comment?(line) when is_binary(line) do
    case String.split(line, "#", parts: 2) do
      [_before, ""] -> false
      [_before, _after] -> true
      [_rest] -> false
    end
  end

  defp comment_block_above?(line_map, line_no) do
    Stream.unfold(line_no - 1, fn
      0 -> nil
      prev -> {Map.get(line_map, prev, ""), prev - 1}
    end)
    |> Enum.take_while(fn text ->
      trimmed = String.trim(text)
      trimmed != "" and String.starts_with?(trimmed, "#")
    end)
    |> Enum.any?()
  end

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Test cases must use `async: true` by default. Only use `async: false` with a strong reason: keep `async: false` and add a comment above (or on) the `use` line explaining WHY the case cannot run async, for example shared global state or a shared database sandbox.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
