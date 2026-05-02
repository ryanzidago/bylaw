defmodule Bylaw.Credo.Check.Readability.ExplicitUnitNames do
  @moduledoc """
  Requires explicit units in ambiguous time and money names.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [app: :bylaw, excluded_paths: []],
    explanations: [
      check: """
      Use explicit units or currencies in ambiguous names such as `timeout`,
      `duration`, or `price`.

      This should be refactored:

          timeout = Keyword.get(opts, :timeout, 5_000)
          System.get_env("COMPLETION_TIMEOUT")
          config :bylaw, :completion_timeout, 5_000
          price = Decimal.new("12.34")

      Into this:

          timeout_ms = Keyword.get(opts, :timeout, 5_000)
          System.get_env("COMPLETION_TIMEOUT_MS")
          config :bylaw, :completion_timeout_ms, 5_000
          price_usd = Decimal.new("12.34")

      The heuristic is intentionally conservative: it only reports local binding
      sites, environment variable names, and application config keys, so atoms
      like `:timeout` used as error reasons are left alone.
      """,
      params: [
        app: "OTP app whose application config keys should be checked.",
        excluded_paths: "List of path prefixes or regexes to exclude from this check."
      ]
    ]

  @definition_forms [:def, :defp, :defmacro, :defmacrop]
  @application_functions [:delete_env, :fetch_env, :fetch_env!, :get_env, :put_env]
  @system_functions [:fetch_env, :fetch_env!, :get_env, :put_env]
  @money_examples ["cents", "usd", "in_cents"]
  @time_examples ["ms", "seconds", "in_ms"]
  @measurements [
    %{
      label: "time",
      stems: MapSet.new(~w(backoff delay duration interval latency timeout ttl)),
      units: MapSet.new(~w(
            d
            day
            days
            h
            hour
            hours
            hr
            hrs
            in_days
            in_hours
            in_ms
            in_minutes
            in_seconds
            m
            min
            mins
            minute
            minutes
            ms
            s
            sec
            second
            seconds
            us
          )),
      examples: @time_examples
    },
    %{
      label: "currency",
      stems: MapSet.new(~w(balance budget cost fee price subtotal total)),
      units: MapSet.new(~w(aud cad cents chf eur gbp in_cents jpy minor_units usd)),
      examples: @money_examples
    }
  ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)
    app = Params.get(params, :app, __MODULE__)

    if excluded?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, app))
    end
  end

  defp traverse({form, _meta, [signature | _body]} = ast, issues, issue_meta, _app)
       when form in @definition_forms do
    {ast, add_identifier_candidates(issues, collect_signature_candidates(signature), issue_meta)}
  end

  defp traverse({match, _meta, [pattern, _rhs]} = ast, issues, issue_meta, _app)
       when match in [:=, :<-] do
    {ast, add_identifier_candidates(issues, collect_bound_identifiers(pattern), issue_meta)}
  end

  defp traverse({:->, _meta, [patterns, _body]} = ast, issues, issue_meta, _app) do
    candidates =
      patterns
      |> List.wrap()
      |> Enum.flat_map(&collect_bound_identifiers/1)

    {ast, add_identifier_candidates(issues, candidates, issue_meta)}
  end

  defp traverse(
         {:@, meta, [{name, name_meta, [_value | _rest]}]} = ast,
         issues,
         issue_meta,
         _app
       )
       when is_atom(name) do
    line_no = name_meta[:line] || meta[:line] || 0
    candidate = %{kind: :identifier, line_no: line_no, name: Atom.to_string(name)}

    {ast, add_candidates(issues, [candidate], issue_meta)}
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:System]}, func]}, meta, args} = ast,
         issues,
         issue_meta,
         _app
       )
       when func in @system_functions and is_list(args) do
    candidates = collect_env_var_candidates(args, meta[:line] || 0)
    {ast, add_candidates(issues, candidates, issue_meta)}
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:Application]}, func]}, meta,
          [app_ast, key_ast | _rest]} = ast,
         issues,
         issue_meta,
         target_app
       )
       when func in @application_functions do
    candidates =
      if matches_app?(app_ast, target_app) do
        collect_app_config_key_candidates(key_ast, meta[:line] || 0)
      else
        []
      end

    {ast, add_candidates(issues, candidates, issue_meta)}
  end

  defp traverse({:config, meta, [app_ast, key_ast | _rest]} = ast, issues, issue_meta, target_app) do
    candidates =
      if matches_app?(app_ast, target_app) do
        collect_app_config_key_candidates(key_ast, meta[:line] || 0)
      else
        []
      end

    {ast, add_candidates(issues, candidates, issue_meta)}
  end

  defp traverse(ast, issues, _issue_meta, _app), do: {ast, issues}

  defp collect_signature_candidates({:when, _meta, [signature | _guards]}),
    do: collect_signature_candidates(signature)

  defp collect_signature_candidates({_name, _meta, args}) when is_list(args) do
    Enum.flat_map(args, &collect_bound_identifiers/1)
  end

  defp collect_signature_candidates(_other), do: []

  defp collect_bound_identifiers({:\\, _meta, [pattern, _default]}),
    do: collect_bound_identifiers(pattern)

  defp collect_bound_identifiers({:^, _meta, [_pinned]}), do: []

  defp collect_bound_identifiers({name, meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    if ignored_identifier?(name) do
      []
    else
      [%{kind: :identifier, line_no: meta[:line] || 0, name: Atom.to_string(name)}]
    end
  end

  defp collect_bound_identifiers(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&collect_bound_identifiers/1)
  end

  defp collect_bound_identifiers(list) when is_list(list) do
    Enum.flat_map(list, &collect_bound_identifiers/1)
  end

  defp collect_bound_identifiers(_other), do: []

  defp collect_env_var_candidates([first_arg | _rest], line_no) do
    case first_arg do
      name when is_binary(name) ->
        [%{kind: :env_var, line_no: line_no, name: name}]

      pairs when is_list(pairs) ->
        Enum.flat_map(pairs, fn
          {name, _value} when is_binary(name) ->
            [%{kind: :env_var, line_no: line_no, name: name}]

          _other ->
            []
        end)

      _other ->
        []
    end
  end

  defp collect_env_var_candidates(_args, _line_no), do: []

  defp collect_app_config_key_candidates(name, line_no) when is_atom(name) do
    [%{kind: :app_config, line_no: line_no, name: Atom.to_string(name)}]
  end

  defp collect_app_config_key_candidates(_other, _line_no), do: []

  defp add_identifier_candidates(issues, candidates, issue_meta) do
    candidates = Enum.uniq(candidates)
    add_candidates(issues, candidates, issue_meta)
  end

  defp add_candidates(issues, candidates, issue_meta) when is_list(candidates) do
    Enum.reduce(candidates, issues, fn candidate, acc ->
      case issue_for(candidate, issue_meta) do
        nil -> acc
        issue -> [issue | acc]
      end
    end)
  end

  defp issue_for(candidate, issue_meta) do
    normalized_name = normalize_name(candidate.name)

    case find_missing_unit(normalized_name) do
      nil ->
        nil

      measurement ->
        trigger = render_trigger(candidate.kind, candidate.name)

        format_issue(
          issue_meta,
          message: issue_message(trigger, candidate, measurement),
          trigger: trigger,
          line_no: candidate.line_no
        )
    end
  end

  defp issue_message(trigger, candidate, measurement) do
    suggestions =
      Enum.map_join(measurement.examples, ", ", fn example ->
        "`#{render_trigger(candidate.kind, "#{candidate.name}_#{example}")}`"
      end)

    "Use explicit #{measurement.label} units in names like `#{trigger}`. " <>
      "Rename it to something like #{suggestions}."
  end

  defp find_missing_unit(name) do
    tokens = tokenize_name(name)

    Enum.find_value(@measurements, fn measurement ->
      Enum.find_value(
        Enum.with_index(tokens),
        &missing_measurement_for_token(&1, tokens, measurement)
      )
    end)
  end

  defp missing_measurement_for_token({token, index}, tokens, measurement) do
    if MapSet.member?(measurement.stems, token) and not explicit_unit?(tokens, index, measurement) do
      measurement
    end
  end

  defp explicit_unit?(tokens, index, measurement) do
    tokens
    |> Enum.drop(index + 1)
    |> Enum.any?(&MapSet.member?(measurement.units, &1))
  end

  defp tokenize_name(name) do
    name
    |> String.replace(~r/[^[:alnum:]_]+/u, "_")
    |> Macro.underscore()
    |> String.split("_", trim: true)
  end

  defp normalize_name(name) do
    name
    |> String.trim_leading(":")
    |> String.trim()
  end

  defp render_trigger(:identifier, name), do: name
  defp render_trigger(:env_var, name), do: String.upcase(name)
  defp render_trigger(:app_config, name), do: ":#{name}"

  defp matches_app?(app_ast, target_app) when is_atom(target_app), do: app_ast == target_app
  defp matches_app?(_app_ast, _target_app), do: false

  defp ignored_identifier?(name) do
    name_string = Atom.to_string(name)
    name == :_ or String.starts_with?(name_string, "_") or String.starts_with?(name_string, "__")
  end

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, fn
      %Regex{} = regex -> Regex.match?(regex, filename)
      path when is_binary(path) -> String.contains?(filename, path)
    end)
  end
end
