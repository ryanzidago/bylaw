Code.require_file("bounded-preparation.exs", __DIR__)
source = Path.join(__DIR__, "preparation-overlap.exs")
quoted = Code.string_to_quoted!(File.read!(source), file: source)

quoted =
  case System.fetch_env!("BYLAW_BOUNDED_UNITS") do
    "aggregate" ->
      quoted

    size ->
      replacement =
        Macro.escape({BylawBoundedStructuralPreparation, unit_size: String.to_integer(size)})

      Macro.postwalk(quoted, fn
        {:__aliases__, _, [:Bylaw, :Contract, :Check, :FunctionClauses]} -> replacement
        node -> node
      end)
  end

Code.eval_quoted(quoted, [], file: source)
