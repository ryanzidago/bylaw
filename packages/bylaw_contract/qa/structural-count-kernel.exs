# Set BYLAW_PROFILE_EBIN and BYLAW_PROFILE_DIRECTORY to explicit paths.
# Run each candidate in a fresh VM, reusing the same fixture path for comparable hashes.
Code.prepend_path(System.fetch_env!("BYLAW_PROFILE_EBIN"))
# Persist a fresh compiled fixture so structural metadata is available.
dir = System.fetch_env!("BYLAW_PROFILE_DIRECTORY")
File.mkdir_p!(dir)
source = Path.join(dir, "fixture.ex")

File.write!(source, """
defmodule BylawThroughputPersisted do
  @spec branch(term()) :: atom()
  def branch(value) when is_integer(value) and value > 0, do: :positive
  def branch(value) when is_integer(value), do: :integer
  def branch(value) when is_atom(value), do: :atom
  def branch(value) when is_map(value), do: :map
  def branch(_), do: :other
end
""")

{:ok, _, _} = Kernel.ParallelCompiler.compile_to_path([source], dir, return_diagnostics: true)
Code.prepend_path(dir)
check = Bylaw.Contract.Check.FunctionClauses
{:ok, initial, _} = check.init([BylawThroughputPersisted], [], %{claims: MapSet.new()})
event = {:call, {BylawThroughputPersisted, :branch, 1}, [42]}

try do
  results =
    for _ <- 1..3 do
      :erlang.garbage_collect()
      {_, before_reductions} = Process.info(self(), :reductions)

      {us, final} =
        :timer.tc(fn ->
          Enum.reduce(1..100_000, initial, fn _, state -> check.observe(event, state) end)
        end)

      {_, after_reductions} = Process.info(self(), :reductions)
      100_000 = final.arity_calls[{BylawThroughputPersisted, :branch, 1}]

      %{
        us: us,
        reductions: after_reductions - before_reductions,
        coverage_hash:
          :crypto.hash(:sha256, :erlang.term_to_binary(check.coverage(final), [:deterministic]))
          |> Base.encode16()
      }
    end

  IO.puts(JSON.encode!(results))
after
  check.terminate(initial)
end
