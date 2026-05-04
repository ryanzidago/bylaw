defmodule Bylaw.Credo.Check.Warning.NoResultTupleArgumentTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Warning.NoResultTupleArgument

  test "flags {:ok, _} as the first argument" do
    """
    defmodule Example do
      def handle({:ok, value}) do
        value
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> assert_issue(%{
      line_no: 2,
      trigger: "{:ok, value}",
      message: ~r/Branch on the result earlier with `case` or `with`/
    })
  end

  test "flags {:error, _} as the first argument when later args exist" do
    """
    defmodule Example do
      defp handle({:error, reason}, conn) when is_map(conn) do
        reason
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> assert_issue(%{
      line_no: 2,
      trigger: "{:error, reason}"
    })
  end

  test "flags a matched first argument when the tuple is on the left side" do
    """
    defmodule Example do
      def handle({:ok, value} = result, other) do
        {result, other, value}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> assert_issue(%{
      line_no: 2,
      trigger: "{:ok, value}"
    })
  end

  test "flags a matched first argument when the tuple is on the right side" do
    """
    defmodule Example do
      def handle(result = {:error, reason}) do
        {result, reason}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> assert_issue(%{
      line_no: 2,
      trigger: "{:error, reason}"
    })
  end

  test "flags multi-element {:ok, ...} tuples as the first argument" do
    """
    defmodule Example do
      def handle({:ok, assistant_message, stream_meta}, other) do
        {assistant_message, stream_meta, other}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> assert_issue(%{
      line_no: 2,
      trigger: "{:ok, assistant_message, stream_meta}"
    })
  end

  test "flags multi-element {:error, ...} tuples as the first argument" do
    """
    defmodule Example do
      def handle({:error, reason, stream_meta}, other) do
        {reason, stream_meta, other}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> assert_issue(%{
      line_no: 2,
      trigger: "{:error, reason, stream_meta}"
    })
  end

  test "flags matched multi-element tuples when the tuple is on the left side" do
    """
    defmodule Example do
      def handle({:ok, assistant_message, stream_meta} = result, other) do
        {assistant_message, stream_meta, result, other}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> assert_issue(%{
      line_no: 2,
      trigger: "{:ok, assistant_message, stream_meta}"
    })
  end

  test "flags matched multi-element tuples when the tuple is on the right side" do
    """
    defmodule Example do
      def handle(result = {:error, reason, stream_meta}, other) do
        {reason, stream_meta, result, other}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> assert_issue(%{
      line_no: 2,
      trigger: "{:error, reason, stream_meta}"
    })
  end

  test "allows tagged tuples outside the first argument" do
    """
    defmodule Example do
      def handle(conn, {:ok, value}) do
        {conn, value}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> refute_issues()
  end

  test "allows branching in the function body" do
    """
    defmodule Example do
      def handle(result) do
        case result do
          {:ok, value} -> value
          {:error, reason} -> reason
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> refute_issues()
  end

  test "allows other tagged tuples in the first argument" do
    """
    defmodule Example do
      def handle({:cont, value}) do
        value
      end
    end
    """
    |> to_source_file()
    |> run_check(NoResultTupleArgument)
    |> refute_issues()
  end
end
