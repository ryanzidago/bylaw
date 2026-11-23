defmodule Bylaw.Credo.Check.Ecto.UseTimestamptzInMigrations do
  @moduledoc """
  Use `:timestamptz` for every time column in an Ecto migration, so each stored
  instant is a Postgres `timestamp with time zone`.

  ## Examples

  Avoid:

        create table(:orders) do
          add :placed_at, :utc_datetime_usec
          add :shipped_at, :naive_datetime
          timestamps(type: :utc_datetime_usec)
        end

  Prefer:

        create table(:orders) do
          add :placed_at, :timestamptz
          add :shipped_at, :timestamptz
          timestamps(type: :timestamptz)
        end

  Principle: "store an instant as an instant".

  In a migration, `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime`,
  `:naive_datetime_usec` and `:timestamp` all create a Postgres
  `timestamp without time zone` column. The names sound zone-aware, but the
  column keeps no zone, so a value read back means whatever the session's time
  zone setting makes it mean. Only `:timestamptz` creates a
  `timestamp with time zone` column, and Postgres stores that in UTC. The
  schema still holds the value as `:utc_datetime_usec`; the column type is
  what this check is about.

  The check looks at files that `use Ecto.Migration` and reports:

  - `add`, `add_if_not_exists` and `modify` with one of those types, also
    inside `{:array, type}`;
  - `timestamps/1` with such a `type:`, `inserted_at_type:` or
    `updated_at_type:`;
  - a `timestamps/1` call with none of those options, which creates
    `timestamp without time zone` columns unless the Repo sets
    `migration_timestamps: [type: :timestamptz]`. Set `:allow_bare_timestamps`
    when it does;
  - an `execute/1` or `execute/2` whose SQL string has a column or cast typed
    `timestamp without time zone`, or a bare `timestamp`.

  It does not report `:date`, `:time` and `:time_usec`, which hold no instant;
  a `modify` that converts a column to `:timestamptz` and names the old type
  in `from:`; or the words `timestamp` in SQL comments and string literals.
  In raw SQL it reads only string literals and sigils, not interpolated
  values or SQL built in a variable, and it reports `timestamp` only where a
  type goes (a cast, or followed by `NOT NULL`, `DEFAULT`, a comma, a
  closing parenthesis and the like), so a column that is named `timestamp`
  does not trigger it.

  Do not use this check for a project whose database is not Postgres, or when a
  column must deliberately hold a local wall-clock time without a zone. A
  migration that has already run cannot be edited: list it in
  `:excluded_paths`, or set `:ignore_migrations_before` to the version
  (the number at the start of the file name) after which the rule applies.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.UseTimestamptzInMigrations,
           [
             allow_bare_timestamps: true,
             ignore_migrations_before: 20261201000000,
             excluded_paths: ["priv/repo/migrations/20261115100200_"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:forbidden_types` - Column types that create a column without a time
    zone. Defaults to `[:naive_datetime, :naive_datetime_usec, :utc_datetime,
    :utc_datetime_usec, :timestamp]`.
  - `:allow_bare_timestamps` - Whether `timestamps/1` without a type option is
    allowed, for a Repo configured with `migration_timestamps: [type:
    :timestamptz]`. Defaults to `false`.
  - `:ignore_migrations_before` - An integer version; migrations whose file
    name starts with a smaller number are skipped. Defaults to `nil`.
  - `:excluded_paths` - Path substrings or regexes of files to skip. Defaults to
    `[]`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.UseTimestamptzInMigrations, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:database],
    param_defaults: [
      forbidden_types: [
        :naive_datetime,
        :naive_datetime_usec,
        :utc_datetime,
        :utc_datetime_usec,
        :timestamp
      ],
      allow_bare_timestamps: false,
      ignore_migrations_before: nil,
      excluded_paths: []
    ],
    explanations: [
      check: @moduledoc,
      params: [
        forbidden_types: "Column types that create a column without a time zone.",
        allow_bare_timestamps:
          "Allow `timestamps/1` without a type option, for a Repo that sets `migration_timestamps: [type: :timestamptz]`.",
        ignore_migrations_before:
          "Skip migrations whose file name starts with a smaller integer version.",
        excluded_paths: "Path substrings or regexes of files to skip."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @column_operations [:add, :add_if_not_exists, :modify]
  @timestamp_type_options [:type, :inserted_at_type, :updated_at_type]
  @fix "use `:timestamptz` (a `timestamp with time zone` column); the Ecto names " <>
         "sound zone-aware but create a column without a zone"

  @without_zone ~r/timestamp(\(\d+\))?\s+without\s+time\s+zone/i
  @cast ~r/::\s*timestamp(\(\d+\))?(?!\w)(?!\s+with\s+time\s+zone)/i
  @typed_position ~r/(?<![\w"])timestamp(\(\d+\))?(?=\s*(,|\)|;|\[|$)|\s+(not|null|default|using|primary|unique|check|references|generated|collate)\b)/i

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    params =
      params
      |> Params.get(__MODULE__)
      |> Map.new()

    ast = Credo.SourceFile.ast(source_file)

    if skip_file?(source_file.filename, params) or not migration?(ast) do
      []
    else
      issue_meta = IssueMeta.for(source_file, [])

      {_ast, issues} =
        Macro.prewalk(ast, [], fn node, acc ->
          {node, findings(node, params, issue_meta) ++ acc}
        end)

      Enum.sort_by(issues, & &1.line_no)
    end
  end

  defp skip_file?(filename, params) do
    RemoteCalls.matches_path?(filename, params.excluded_paths) or
      before_cut_off?(filename, params.ignore_migrations_before)
  end

  defp before_cut_off?(_filename, nil), do: false

  defp before_cut_off?(filename, cut_off) do
    basename = Path.basename(filename)

    case Integer.parse(basename) do
      {version, _rest} -> version < cut_off
      :error -> false
    end
  end

  defp migration?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:use, _meta, [{:__aliases__, _alias_meta, [:Ecto, :Migration]} | _opts]} = node, _acc ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp findings({operation, meta, [name, type | _rest]}, params, issue_meta)
       when operation in @column_operations do
    if forbidden?(type, params) do
      [
        issue(
          issue_meta,
          meta,
          operation,
          "Column #{inspect_name(name)} has type #{inspect_type(type)}"
        )
      ]
    else
      []
    end
  end

  defp findings({:timestamps, meta, args}, params, issue_meta)
       when is_list(args) or is_nil(args) do
    opts = timestamp_options(args)
    typed = Enum.filter(opts, fn {key, _value} -> key in @timestamp_type_options end)

    cond do
      Enum.any?(typed, fn {_key, type} -> forbidden?(type, params) end) ->
        [issue(issue_meta, meta, :timestamps, "`timestamps` uses a type without a time zone")]

      typed == [] and not params.allow_bare_timestamps ->
        [
          issue(
            issue_meta,
            meta,
            :timestamps,
            "`timestamps` without `type: :timestamptz` creates columns without a time zone"
          )
        ]

      true ->
        []
    end
  end

  defp findings({:execute, meta, [_sql | _rest] = args}, _params, issue_meta) do
    if Enum.any?(args, &zoneless_sql?/1) do
      [
        issue(
          issue_meta,
          meta,
          :execute,
          "SQL in `execute` types a column or cast as a timestamp without a time zone"
        )
      ]
    else
      []
    end
  end

  defp findings(_node, _params, _issue_meta), do: []

  defp timestamp_options([opts]) when is_list(opts), do: Enum.filter(opts, &match?({_, _}, &1))
  defp timestamp_options(_args), do: []

  defp forbidden?({:array, type}, params), do: forbidden?(type, params)
  defp forbidden?(type, params) when is_atom(type), do: type in params.forbidden_types
  defp forbidden?(_type, _params), do: false

  defp zoneless_sql?(ast) do
    case sql_text(ast) do
      nil ->
        false

      sql ->
        sql = strip_sql(sql)

        Regex.match?(@without_zone, sql) or Regex.match?(@cast, sql) or
          Regex.match?(@typed_position, sql)
    end
  end

  defp sql_text(text) when is_binary(text), do: text

  defp sql_text({sigil, _meta, [{:<<>>, _parts_meta, parts}, _modifiers]})
       when sigil in [:sigil_s, :sigil_S], do: literal_parts(parts)

  defp sql_text({:<<>>, _meta, parts}), do: literal_parts(parts)
  defp sql_text(_ast), do: nil

  defp literal_parts(parts) do
    Enum.map_join(parts, fn
      part when is_binary(part) -> part
      _interpolation -> " "
    end)
  end

  defp strip_sql(sql) do
    sql
    |> String.replace(~r/--[^\n]*/, " ")
    |> String.replace(~r{/\*.*?\*/}s, " ")
    |> String.replace(~r/'(?:[^']|'')*'/, "''")
  end

  defp inspect_name(name) when is_atom(name) or is_binary(name), do: "`#{inspect(name)}`"
  defp inspect_name(_name), do: "`...`"

  defp inspect_type({:array, type}), do: "{:array, #{inspect(type)}}"
  defp inspect_type(type), do: inspect(type)

  defp issue(issue_meta, meta, operation, subject) do
    format_issue(issue_meta,
      message: "#{subject}; #{@fix}.",
      trigger: Atom.to_string(operation),
      line_no: meta[:line]
    )
  end
end
