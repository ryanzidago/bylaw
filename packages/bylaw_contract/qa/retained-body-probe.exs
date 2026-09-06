# Fresh-VM preparation diagnostic; forced collections are outside phase timings.
defmodule BylawRetainedBodyProbe do
  @moduledoc false

  @doc false
  @spec run(list(module()), boolean()) :: map()
  def run(modules, fixture?) do
    alias Bylaw.Contract.StructuralCoverage
    {ensure_us, _} = :timer.tc(fn -> Enum.each(modules, &Code.ensure_loaded/1) end)
    :erlang.garbage_collect()
    before_load = memory()
    {load_us, loaded} = :timer.tc(fn -> StructuralCoverage.load(modules) end)
    :erlang.garbage_collect()
    after_load = memory()
    wordsize = :erlang.system_info(:wordsize)
    plan_flat_bytes = :erts_debug.flat_size(loaded.classifiers) * wordsize
    plan_shared_bytes = :erts_debug.size(loaded.classifiers) * wordsize
    loaded_shared_bytes = :erts_debug.size(loaded) * wordsize
    source_md5s = Map.new(modules, &{inspect(&1), &1.module_info(:md5) |> Base.encode16()})

    {shadow_us, {:ok, shadow}} =
      :timer.tc(fn -> StructuralCoverage.start_shadow(loaded.classifiers) end)

    after_shadow = memory()
    shadow_md5 = shadow.module_info(:md5) |> Base.encode16()

    {stop_us, :ok} =
      try do
        if fixture? do
          true = length(loaded.clauses) == length(modules) * 2
          true = length(loaded.arities) == length(modules)
          true = Enum.empty?(loaded.warnings)

          for module <- modules do
            classifier = %{classifier_function: module, source_function: :total, source_arity: 1}

            {1, [{true, true}, {false, false}]} =
              StructuralCoverage.classify(shadow, classifier, [3], self())

            {2, [{true, false}, {true, true}]} =
              StructuralCoverage.classify(shadow, classifier, [:skip], self())

            {1, [{true, true}, {false, false}]} =
              StructuralCoverage.classify(shadow, classifier, [-1], self())
          end
        end

        :timer.tc(fn -> StructuralCoverage.stop_shadow(shadow) end)
      after
        if :code.is_loaded(shadow) != false, do: StructuralCoverage.stop_shadow(shadow)
      end

    false = :code.is_loaded(shadow)
    semantic_hash = loaded |> without_bodies() |> fingerprint()
    ^source_md5s = Map.new(modules, &{inspect(&1), &1.module_info(:md5) |> Base.encode16()})

    %{
      modules: length(modules),
      classifiers: length(loaded.classifiers),
      clauses: length(loaded.clauses),
      arities: length(loaded.arities),
      warnings: loaded.warnings,
      ensure_us: ensure_us,
      load_us: load_us,
      shadow_us: shadow_us,
      stop_us: stop_us,
      plan_flat_bytes: plan_flat_bytes,
      plan_shared_bytes: plan_shared_bytes,
      loaded_shared_bytes: loaded_shared_bytes,
      before_load: before_load,
      after_load: after_load,
      after_shadow: after_shadow,
      semantic_sha256: semantic_hash,
      shadow_md5: shadow_md5,
      source_md5s: source_md5s,
      cleanup: true,
      fixture_oracle: fixture?
    }
  end

  defp without_bodies(loaded) do
    update_in(loaded.classifiers, fn classifiers ->
      Enum.map(classifiers, fn classifier ->
        update_in(classifier.mfa_classifiers, fn mfas ->
          Enum.map(mfas, fn mfa ->
            update_in(mfa.clauses, fn clauses ->
              Enum.map(clauses, fn entry ->
                {:clause, annotation, patterns, guards, _} = entry.clause
                %{entry | clause: {:clause, annotation, patterns, guards, []}}
              end)
            end)
          end)
        end)
      end)
    end)
  end

  defp fingerprint(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  defp memory do
    Map.put(
      Map.new(:erlang.memory([:total, :processes, :binary, :code, :ets])),
      :probe_process,
      Process.info(self(), :memory) |> elem(1)
    )
  end
end

Code.prepend_path(System.fetch_env!("BYLAW_BODY_EBIN"))
fixture? = System.get_env("BYLAW_BODY_MODULE_COUNT") != nil

modules =
  if fixture? do
    for index <- 1..String.to_integer(System.fetch_env!("BYLAW_BODY_MODULE_COUNT")),
        do: Module.concat(BylawBodyFixture, "Module#{index}")
  else
    app = System.fetch_env!("BYLAW_BODY_APP") |> String.to_atom()
    Application.load(app)
    Application.spec(app, :modules) |> Enum.sort()
  end

result = BylawRetainedBodyProbe.run(modules, fixture?)
:erlang.garbage_collect()

result =
  Map.put(
    result,
    :after_release,
    Map.new(:erlang.memory([:total, :processes, :binary, :code, :ets]))
  )

File.write!(System.fetch_env!("BYLAW_BODY_OUTPUT"), JSON.encode!(result) <> "\n")
