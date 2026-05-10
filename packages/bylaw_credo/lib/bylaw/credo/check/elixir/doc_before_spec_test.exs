defmodule Bylaw.Credo.Check.Elixir.DocBeforeSpecTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.DocBeforeSpec

  test "reports when @spec appears before @doc for a public function" do
    """
    defmodule Example do
      @spec handle(result :: term()) :: :ok
      @doc "Handles the result."
      def handle(result), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> assert_issue()
  end

  test "does not report when @doc appears before @spec" do
    """
    defmodule Example do
      @doc "Handles the result."
      @spec handle(result :: term()) :: :ok
      def handle(result), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> refute_issues()
  end

  test "does not report when @spec is present without @doc" do
    """
    defmodule Example do
      @spec handle(result :: term()) :: :ok
      def handle(result), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> refute_issues()
  end

  test "does not report when @doc is present without @spec" do
    """
    defmodule Example do
      @doc "Handles the result."
      def handle(result), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> refute_issues()
  end

  test "does not report when @impl appears before the doc and spec" do
    """
    defmodule Example do
      @behaviour Plug

      @impl Plug
      @doc "Handles the connection."
      @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
      def call(conn, _opts), do: conn
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> refute_issues()
  end

  test "allows multiple specs after the doc" do
    """
    defmodule Example do
      @doc "Handles the result."
      @spec handle(result :: atom()) :: :ok
      @spec handle(result :: integer()) :: :ok
      def handle(result), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> refute_issues()
  end

  test "reports when any spec appears before the doc" do
    """
    defmodule Example do
      @spec handle(result :: atom()) :: :ok
      @doc false
      @spec handle(result :: integer()) :: :ok
      def handle(result), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> assert_issue()
  end

  test "reports for public macros when @spec appears before @doc" do
    """
    defmodule Example do
      @spec quoted(atom()) :: Macro.t()
      @doc "Builds quoted output."
      defmacro quoted(name) do
        quote do
          unquote(name)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> assert_issue()
  end

  test "reports for guards when @spec appears before @doc" do
    """
    defmodule Example do
      @spec positive?(integer()) :: boolean()
      @doc "Checks whether the value is positive."
      defguard positive?(value) when is_integer(value) and value > 0
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> assert_issue()
  end

  test "ignores docs used for non-function declarations" do
    """
    defmodule Example do
      @doc "Documents a callback."
      @callback handle(result :: term()) :: :ok

      @spec run() :: :ok
      def run, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> refute_issues()
  end

  test "does not leak attrs across nested modules" do
    """
    defmodule Example do
      @doc "Documents the outer helper."
      @spec helper() :: :ok

      defmodule Nested do
        @doc "Nested public API."
        @spec run() :: :ok
        def run, do: :ok
      end

      def helper, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocBeforeSpec)
    |> refute_issues()
  end
end
