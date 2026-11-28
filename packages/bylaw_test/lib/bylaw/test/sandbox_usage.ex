defmodule Bylaw.Test.SandboxUsage do
  @moduledoc """
  Detects ExUnit tests that checked out a database sandbox without executing a real SQL query.

  Start `Bylaw.Test.SandboxUsage` and register `Bylaw.Test.SandboxUsage.Formatter` and
  `ExUnit.after_suite(&Bylaw.Test.SandboxUsage.check!/1)` in `test/test_helper.exs`. Call
  `watch/2` from your database case template setup (`DataCase` / `ConnCase`). Any passing
  watched test that completes with zero non-plumbing SQL queries fails `check!/1`, telling
  the author to move the test to `ExUnit.Case` or skip the sandbox checkout.
  """

  use GenServer

  alias Bylaw.Test.SandboxUsage.Violation

  @plumbing_sql ~r/\A\s*(begin|commit|rollback|savepoint|release\s+savepoint|rollback\s+to\s+savepoint)\b/i

  @typedoc "Matcher for SQL queries ignored when deciding whether a test used the database."
  @type ignore_matcher :: Regex.t() | (String.t() -> boolean())

  @typedoc "Options passed to `start_link/1`."
  @type start_option ::
          {:events, list(list(atom()))}
          | {:ignore, list(ignore_matcher())}
          | {:name, GenServer.name()}

  @typedoc "Options passed to `watch/2`."
  @type watch_option :: {:server, GenServer.server()} | {:shared, boolean()}

  @typedoc "Options passed to `violations/1` and `check!/2`."
  @type check_option :: {:server, GenServer.server()}

  @doc "Starts the sandbox-usage tracker and attaches telemetry handlers to `events`."
  @spec start_link(opts :: list(start_option())) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:events, ignore: [], name: __MODULE__])
    events = validate_events!(Keyword.fetch!(opts, :events))
    ignore = validate_ignore!(Keyword.fetch!(opts, :ignore))
    name = Keyword.fetch!(opts, :name)

    GenServer.start_link(__MODULE__, %{events: events, ignore: ignore, name: name}, name: name)
  end

  @doc "Returns whether `server` is currently running."
  @spec running?(server :: GenServer.server()) :: boolean()
  def running?(server \\ __MODULE__) do
    GenServer.whereis(server) != nil
  end

  @doc "Watches the current ExUnit test for real SQL queries."
  @spec watch(context :: map()) :: :ok
  def watch(context) when is_map(context), do: watch(context, [])

  @doc "Watches the current ExUnit test for real SQL queries with explicit `opts`."
  @spec watch(context :: map(), opts :: list(watch_option())) :: :ok
  def watch(context, opts) when is_map(context) and is_list(opts) do
    opts =
      Keyword.validate!(opts, server: __MODULE__, shared: not Map.get(context, :async, false))

    server = Keyword.fetch!(opts, :server)
    shared = Keyword.fetch!(opts, :shared)
    table = table!(server)

    module = Map.get(context, :module) || Map.fetch!(context, :case)
    test_name = Map.fetch!(context, :test)
    test_key = {module, test_name}
    owner_pid = self()

    true =
      :ets.insert(
        table,
        {{:watched, test_key}, %{file: Map.get(context, :file), line: Map.get(context, :line)}}
      )

    true = :ets.insert(table, {{:pid, owner_pid}, test_key})

    if shared do
      true = :ets.insert(table, {{:shared, test_key}, true})
    end

    ExUnit.Callbacks.on_exit(fn ->
      untrack_owner(table, owner_pid, test_key, shared)
    end)

    :ok
  end

  @doc "Returns sorted violations recorded for passing watched tests with zero SQL queries."
  @spec violations() :: list(Violation.t())
  def violations, do: violations([])

  @doc "Returns sorted violations recorded by the configured `server`."
  @spec violations(opts :: list(check_option())) :: list(Violation.t())
  def violations(opts) when is_list(opts) do
    opts = Keyword.validate!(opts, server: __MODULE__)
    table = table!(Keyword.fetch!(opts, :server))

    table
    |> :ets.match_object({{:violation, :_}, :_})
    |> Enum.map(fn {{:violation, _key}, violation} -> violation end)
    |> Enum.sort_by(fn violation ->
      {violation.file || "", violation.line || 0, inspect(violation.module), violation.test}
    end)
  end

  @doc "Formats `violations` into an actionable ExUnit failure message."
  @spec format_violations(violations :: list(Violation.t())) :: String.t()
  def format_violations(violations) when is_list(violations) do
    details =
      Enum.map_join(violations, "\n", fn violation ->
        location = format_location(violation.file, violation.line)
        "  - #{location} — #{inspect(violation.module)} #{inspect(violation.test)}"
      end)

    """
    Tests checked out a database sandbox without running any SQL queries:

    #{details}

    Move database-independent tests to `ExUnit.Case` (or disable the sandbox checkout for non-DB connection tests).
    """
  end

  @doc "`ExUnit.after_suite/1` callback that fails when any passing watched test ran zero queries."
  @spec check!(suite_result :: map()) :: :ok
  def check!(suite_result), do: check!(suite_result, [])

  @doc "`ExUnit.after_suite/1` callback scoped by `opts`."
  @spec check!(suite_result :: map(), opts :: list(check_option())) :: :ok
  def check!(_suite_result, opts) when is_list(opts) do
    found = violations(opts)

    if Enum.empty?(found) do
      :ok
    else
      ExUnit.Assertions.flunk(format_violations(found))
    end
  end

  @doc false
  @spec record_test_finished(
          server :: GenServer.server(),
          test_key :: {module(), atom()},
          outcome :: :passed | :not_passed
        ) :: :ok
  def record_test_finished(server, test_key, outcome) do
    case lookup_table(server) do
      {:ok, table} ->
        case :ets.lookup(table, {:watched, test_key}) do
          [{{:watched, ^test_key}, %{file: file, line: line}}] ->
            if outcome == :passed and not :ets.member(table, {:queried, test_key}) do
              {module, test_name} = test_key

              violation = %Violation{
                module: module,
                test: test_name,
                file: file,
                line: line
              }

              true = :ets.insert(table, {{:violation, test_key}, violation})
            end

            true = :ets.delete(table, {:watched, test_key})
            true = :ets.delete(table, {:queried, test_key})
            :ok

          [] ->
            :ok
        end

      :error ->
        :ok
    end
  end

  @doc false
  @spec handle_query(
          event :: list(atom()),
          measurements :: map(),
          metadata :: map(),
          config :: %{table: :ets.tid(), ignore: list(ignore_matcher())}
        ) :: :ok
  def handle_query(_event, _measurements, %{query: query}, %{table: table, ignore: ignore})
      when is_binary(query) do
    if ignored_query?(query, ignore) do
      :ok
    else
      credit_active_tests(table)
    end
  end

  def handle_query(_event, _measurements, _metadata, _config), do: :ok

  @impl GenServer
  def init(%{events: events, ignore: ignore, name: name}) do
    Process.flag(:trap_exit, true)

    table =
      :ets.new(__MODULE__, [
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    handler_id = "bylaw-test-sandbox-usage-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_query/4,
        %{table: table, ignore: ignore}
      )

    :persistent_term.put(term_key(self()), table)

    if is_atom(name) do
      :persistent_term.put(term_key(name), table)
    end

    {:ok, %{table: table, handler_id: handler_id, name: name}}
  end

  @impl GenServer
  def terminate(_reason, %{handler_id: handler_id, name: name}) do
    _ = :telemetry.detach(handler_id)
    _ = :persistent_term.erase(term_key(self()))

    if is_atom(name) do
      _ = :persistent_term.erase(term_key(name))
    end

    :ok
  end

  defp validate_events!(events) when is_list(events) do
    valid? =
      not Enum.empty?(events) and
        Enum.all?(events, fn event ->
          is_list(event) and not Enum.empty?(event) and Enum.all?(event, &is_atom/1)
        end)

    unless valid? do
      raise ArgumentError,
            "expected :events to be a non-empty list of non-empty telemetry event atom lists"
    end

    events
  end

  defp validate_events!(_events) do
    raise ArgumentError,
          "expected :events to be a non-empty list of non-empty telemetry event atom lists"
  end

  defp validate_ignore!(ignore) when is_list(ignore) do
    valid? =
      Enum.all?(ignore, fn
        %Regex{} -> true
        fun when is_function(fun, 1) -> true
        _other -> false
      end)

    unless valid? do
      raise ArgumentError, "expected :ignore entries to be Regex structs or 1-arity functions"
    end

    ignore
  end

  defp validate_ignore!(_ignore) do
    raise ArgumentError, "expected :ignore to be a list of Regex structs or 1-arity functions"
  end

  defp table!(server) do
    case lookup_table(server) do
      {:ok, table} ->
        table

      :error ->
        raise RuntimeError,
              "#{inspect(server)} is not running; start Bylaw.Test.SandboxUsage in test_helper.exs"
    end
  end

  defp lookup_table(server) when is_pid(server), do: fetch_term(server)
  defp lookup_table(server) when is_atom(server), do: fetch_term(server)

  defp lookup_table(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> fetch_term(pid)
      nil -> :error
    end
  end

  defp fetch_term(key) do
    case :persistent_term.get(term_key(key), nil) do
      nil -> :error
      table -> {:ok, table}
    end
  end

  defp term_key(key), do: {__MODULE__, key}

  defp untrack_owner(table, owner_pid, test_key, shared) do
    if :ets.info(table) != :undefined do
      true = :ets.delete(table, {:pid, owner_pid})

      if shared do
        true = :ets.delete(table, {:shared, test_key})
      end
    end

    :ok
  end

  defp ignored_query?(query, ignore) do
    Regex.match?(@plumbing_sql, query) or
      Enum.any?(ignore, fn
        %Regex{} = pattern -> Regex.match?(pattern, query)
        fun when is_function(fun, 1) -> fun.(query)
      end)
  end

  defp credit_active_tests(table) do
    if :ets.info(table) == :undefined do
      :ok
    else
      do_credit_active_tests(table)
    end
  end

  defp do_credit_active_tests(table) do
    chain = [self() | Process.get(:"$callers", [])]

    matched_keys =
      Enum.flat_map(chain, fn pid ->
        case :ets.lookup(table, {:pid, pid}) do
          [{{:pid, ^pid}, test_key}] -> [test_key]
          [] -> []
        end
      end)

    keys =
      if Enum.empty?(matched_keys) do
        table
        |> :ets.match({{:shared, :"$1"}, true})
        |> Enum.map(fn [test_key] -> test_key end)
      else
        matched_keys
      end

    Enum.each(keys, fn test_key ->
      true = :ets.insert(table, {{:queried, test_key}, true})
    end)

    :ok
  end

  defp format_location(nil, _line), do: "<unknown>"
  defp format_location(file, nil), do: file
  defp format_location(file, line), do: "#{file}:#{line}"
end
