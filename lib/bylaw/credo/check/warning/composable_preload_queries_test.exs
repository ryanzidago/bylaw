defmodule Bylaw.Credo.Check.Warning.ComposablePreloadQueriesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Warning.ComposablePreloadQueries

  describe "reports issues" do
    test "literal preloads inside preload query helpers" do
      """
      defmodule Example do
        import Ecto.Query

        defp input_file_preload_query do
          ToolCallFile
          |> from(as: :tool_file)
          |> preload([:file])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(ComposablePreloadQueries)
      |> assert_issue(%{
        line_no: 7,
        trigger: "preload",
        message: ~r/preload\(\^preloads\)/
      })
    end

    test "binding-aware literal preloads inside preload query helpers" do
      """
      defmodule Example do
        import Ecto.Query

        defp input_file_preload_query do
          ToolCallFile
          |> from(as: :tool_file)
          |> preload([tool_file: tf], [:file])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(ComposablePreloadQueries)
      |> assert_issue(%{
        line_no: 7,
        trigger: "preload"
      })
    end

    test "keyword preloads inside preload query helpers" do
      """
      defmodule Example do
        import Ecto.Query

        def message_preload_query do
          Message
          |> from(as: :message)
          |> preload([], message_files: ^message_file_preload_query(preloads: [:file]))
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(ComposablePreloadQueries)
      |> assert_issue(%{
        line_no: 7,
        trigger: "preload"
      })
    end

    test "remote Ecto.Query.preload calls inside preload query helpers" do
      """
      defmodule Example do
        defp input_file_preload_query(query) do
          Ecto.Query.preload(query, [:file])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(ComposablePreloadQueries)
      |> assert_issue(%{
        line_no: 3,
        trigger: "Ecto.Query.preload"
      })
    end

    test "pinned preloads that are hard-coded locally inside preload query helpers" do
      """
      defmodule Example do
        import Ecto.Query

        defp input_file_preload_query do
          preloads = [:file]

          ToolCallFile
          |> from(as: :tool_file)
          |> preload(^preloads)
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(ComposablePreloadQueries)
      |> assert_issue(%{
        line_no: 9,
        trigger: "preload"
      })
    end
  end

  describe "does not report issues" do
    test "dynamic preloads inside preload query helpers" do
      """
      defmodule Example do
        import Ecto.Query

        defp input_file_preload_query(opts) do
          preloads = Keyword.get(opts, :preloads, [])

          ToolCallFile
          |> from(as: :tool_file)
          |> preload(^preloads)
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(ComposablePreloadQueries)
      |> refute_issues()
    end

    test "hard-coded preloads outside preload query helpers" do
      """
      defmodule Example do
        import Ecto.Query

        def fetch_message(id) do
          Message
          |> where([message: m], m.id == ^id)
          |> preload([:message_files])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(ComposablePreloadQueries)
      |> refute_issues()
    end

    test "Repo.preload is out of scope" do
      """
      defmodule Example do
        alias Bylaw.Repo

        defp input_file_preload_query(record) do
          Repo.preload(record, [:file])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(ComposablePreloadQueries)
      |> refute_issues()
    end
  end
end
