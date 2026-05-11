# Bylaw.Ecto.Query

Ecto query validation APIs and checks for Bylaw.

Use this package to validate prepared `Ecto.Query` structs before they run.
Callers choose checks explicitly and pass them to
`Bylaw.Ecto.Query.validate/3`.

## Installation

Add `:bylaw_ecto_query` to your dependencies:

```elixir
def deps do
  [
    {:bylaw_ecto_query, "~> 0.1.0-alpha.1"}
  ]
end
```

## Usage

For repo-wide validation, choose the query checks you want to enforce and pass
them explicitly to `Bylaw.Ecto.Query.validate/3` from
`c:Ecto.Repo.prepare_query/3`:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @query_checks [
    Bylaw.Ecto.Query.Checks.RequiredOrder,
    Bylaw.Ecto.Query.Checks.DeterministicOrder,
    {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys, keys: [:organization_id]}
  ]

  @impl Ecto.Repo
  def prepare_query(operation, query, opts) do
    case Bylaw.Ecto.Query.validate(operation, query, @query_checks) do
      :ok -> {query, opts}
      {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
    end
  end
end
```

If you want to enable validation only in certain environments, gate the call
with your own application config:

```elixir
# config/dev.exs and config/test.exs
config :my_app, :bylaw, validate_ecto_queries?: true

# config/prod.exs
config :my_app, :bylaw, validate_ecto_queries?: false
```

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @query_checks [
    Bylaw.Ecto.Query.Checks.RequiredOrder,
    {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys, keys: [:organization_id]}
  ]

  @impl Ecto.Repo
  def prepare_query(operation, query, opts) do
    if bylaw_ecto_query_enabled?() do
      validate_query!(operation, query)
    end

    {query, opts}
  end

  defp validate_query!(operation, query) do
    case Bylaw.Ecto.Query.validate(operation, query, @query_checks) do
      :ok -> :ok
      {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
    end
  end

  defp bylaw_ecto_query_enabled? do
    :my_app
    |> Application.get_env(:bylaw, [])
    |> Keyword.get(:validate_ecto_queries?, false)
  end
end
```

This config belongs to `:my_app`. `bylaw_ecto_query` does not read application
config or register checks globally.

Built-in checks live under `Bylaw.Ecto.Query.Checks.*`. Start with the checks
that match your application invariants; each check module documents its own
examples, notes, options, and copyable check specs.
