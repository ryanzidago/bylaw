# All captures must be supplied explicitly; rejected/incomplete rows cannot pass.
paths = System.argv()
true = Enum.any?(paths)

for path <- paths do
  result = path |> File.read!() |> :erlang.binary_to_term()
  %{passed: 12} = result.test_states
  true = Enum.empty?(result.failures)
  %{docs: false, debug_info: false, infer_signatures: false} = result.compiler_options

  unless result.mode == "disabled" do
    c = result.coverage
    :complete = Map.get(c, :status, :complete)

    for {check, data} <- c.checks do
      case check do
        Bylaw.Contract.Check.Typespec ->
          12 = map_size(data.calls)
          12 = map_size(data.return_events)
          true = Enum.all?(data.calls, fn {_, n} -> n == 20 end)
          true = Enum.all?(data.return_events, fn {_, n} -> n == 20 end)
          for target <- data.return_alternatives, do: 10 = Map.fetch!(data.hits, target.id)

        Bylaw.Contract.Check.FunctionClauses ->
          24 = map_size(data.arity_calls)
          true = Enum.all?(data.arity_calls, fn {_, n} -> n == 20 end)
          48 = length(data.clauses)

          for clause <- data.clauses do
            expected =
              if clause.function == :choose,
                do: %{selected: 10, guard_passes: 10, guard_rejections: 0, head_matches: 10},
                else:
                  if(clause.position == 1,
                    do: %{selected: 10, guard_passes: 10, guard_rejections: 10, head_matches: 20},
                    else: %{selected: 10, guard_passes: 20, guard_rejections: 0, head_matches: 20}
                  )

            ^expected = Map.fetch!(data.clause_outcomes, clause.id)
          end

        Bylaw.Contract.Check.ElixirCompiler ->
          # Compiler-only preparation has a public default cap of ten functions.
          # Combined mode honors the Typespec check's prior return claims.
          if result.mode in ["compiler", "all"] do
            10 = map_size(data.compiler_calls)
            true = Enum.all?(data.compiler_calls, fn {_, n} -> n == 20 end)
          end
      end
    end
  end
end

IO.puts("Verified exact independent fixture counters in #{length(paths)} captures")
