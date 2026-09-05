defmodule Bylaw.Contract.CheckCallerContextTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.CallerGuardFixture, as: Fixture

  defmodule LegacyCheck do
    @behaviour Bylaw.Contract.Check

    @impl Bylaw.Contract.Check
    def init([module], [], _context) do
      mfas = MapSet.new([{module, :who, 1}])
      {:ok, [], %{calls: mfas, returns: mfas, claims: MapSet.new()}}
    end

    @impl Bylaw.Contract.Check
    def observe(event, events), do: [{event, self()} | events]

    @impl Bylaw.Contract.Check
    def coverage(events), do: %{events: Enum.reverse(events)}

    @impl Bylaw.Contract.Check
    def terminate(_events), do: :ok
  end

  defmodule ContextCheck do
    @behaviour Bylaw.Contract.Check

    @impl Bylaw.Contract.Check
    defdelegate init(modules, opts, context), to: LegacyCheck

    @impl Bylaw.Contract.Check
    defdelegate observe(event, events), to: LegacyCheck

    @impl Bylaw.Contract.Check
    def observe(event, caller, events), do: [{event, caller, self()} | events]

    @impl Bylaw.Contract.Check
    defdelegate coverage(events), to: LegacyCheck

    @impl Bylaw.Contract.Check
    defdelegate terminate(events), to: LegacyCheck
  end

  test "legacy checks keep original call and return event tuples" do
    caller = self()
    {worker, events} = capture(LegacyCheck)
    refute worker == caller

    assert events == [
             {{:call, {Fixture, :who, 1}, [caller]}, worker},
             {{:return, {Fixture, :who, 1}, :caller}, worker}
           ]
  end

  test "opted-in checks receive producer identities for calls and returns" do
    caller = self()
    {worker, events} = capture(ContextCheck)
    refute worker == caller

    assert events == [
             {{:call, {Fixture, :who, 1}, [caller]}, caller, worker},
             {{:return, {Fixture, :who, 1}, :caller}, caller, worker}
           ]
  end

  defp capture(check) do
    {:ok, observer} = Contract.start([Fixture], checks: [check])

    try do
      [worker] = :sys.get_state(observer).workers
      assert Fixture.who(self()) == :caller
      coverage = Contract.stop(observer)
      refute Map.has_key?(coverage, :incomplete)
      {worker, coverage.checks[check].events}
    after
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end
end
