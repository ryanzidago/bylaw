defmodule Bylaw.Contract.TraceQueueBudget do
  @moduledoc false

  @doc false
  @spec start(owner :: pid(), session :: term(), limit :: pos_integer()) :: map()
  def start(owner, session, limit) do
    budget = %{owner: owner, session: session, limit: limit, exceeded: :atomics.new(1, [])}
    pid = spawn_link(fn -> watch(budget, Process.monitor(owner)) end)
    Map.put(budget, :pid, pid)
  end

  @doc false
  @spec check(budget :: map() | nil, in_flight :: non_neg_integer()) :: non_neg_integer()
  def check(budget, in_flight \\ 0)
  def check(nil, _in_flight), do: 0

  def check(budget, in_flight) do
    case :atomics.get(budget.exceeded, 1) do
      0 -> inspect_queue(budget, in_flight)
      count -> count
    end
  end

  @doc false
  @spec stop(budget :: map() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(budget) do
    monitor = Process.monitor(budget.pid)
    send(budget.pid, :stop)

    receive do
      {:DOWN, ^monitor, :process, _, _} -> :ok
    end
  end

  @doc false
  @spec reason(budget :: map() | nil, check :: module()) :: list(map())
  def reason(nil, _check), do: []

  def reason(budget, check) do
    case :atomics.get(budget.exceeded, 1) do
      0 -> []
      count -> [%{check: check, reason: :trace_queue_limit, limit: budget.limit, observed: count}]
    end
  end

  defp inspect_queue(budget, in_flight) do
    case Process.info(budget.owner, :message_queue_len) do
      {:message_queue_len, count} when count + in_flight > budget.limit ->
        count = count + in_flight
        :atomics.compare_exchange(budget.exceeded, 1, 0, count)
        :trace.session_destroy(budget.session)
        :atomics.get(budget.exceeded, 1)

      _ ->
        0
    end
  end

  defp watch(budget, monitor) do
    check(budget)

    receive do
      :stop -> :ok
      {:DOWN, ^monitor, :process, _, _} -> :ok
    after
      5 -> watch(budget, monitor)
    end
  end
end
