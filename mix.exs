defmodule Bylaw.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ryanzidago/bylaw"

  def project do
    [
      app: :bylaw,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: test_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: dialyzer(),
      usage_rules: usage_rules(),
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/bylaw",
      description: description(),
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp test_paths(:test), do: ["lib"]
  defp test_paths(_env), do: ["test"]

  def cli do
    [
      preferred_envs: [
        qa: :test,
        dialyzer: :test,
        "test.postgres": :test
      ]
    ]
  end

  defp aliases do
    [
      qa: &run_qa/1,
      "test.postgres": [
        "ecto.drop --quiet --force",
        "ecto.create --quiet",
        "test --include postgres"
      ]
    ]
  end

  defp run_qa(args) do
    "scripts/qa.exs"
    |> Path.expand(__DIR__)
    |> Code.require_file()

    Bylaw.Dev.Qa.run(args)
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13", only: :test},
      {:ex_doc, "~> 0.39", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:postgrex, "~> 0.22.0", only: :test},
      {:usage_rules, "~> 1.2", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:credo, :ex_unit, :mix],
      plt_local_path: "priv/plts"
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [{:usage_rules, sub_rules: ["otp"]}]
    ]
  end

  defp description do
    "Validation helpers for code, database, query, schema, and workflow constraints."
  end

  defp package do
    [
      files:
        Path.wildcard("lib/**/*.ex") ++
          ~w(guides .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "checks",
      source_ref: "v#{@version}",
      skip_code_autolink_to: [
        "Bylaw.Credo",
        "Bylaw.Db",
        "Bylaw.Ecto.Query",
        "Bylaw.Ecto.Query.Checks"
      ],
      extras: [
        "README.md",
        "guides/checks.md": [title: "Checks Overview"],
        "guides/ecto_query_checks.md": [title: "Bylaw.Ecto.Query Checks"]
      ],
      groups_for_extras: [
        Guides: ~r/guides\//
      ],
      groups_for_modules: [
        Core: [Bylaw],
        "Bylaw.Ecto.Query": [
          Bylaw.Ecto.Query,
          Bylaw.Ecto.Query.Check,
          Bylaw.Ecto.Query.Issue
        ],
        "Bylaw.Ecto.Query checks": ~r/^(Elixir\.)?Bylaw\.Ecto\.Query\.Checks\./,
        "Bylaw.Db": [
          Bylaw.Db,
          Bylaw.Db.Adapter,
          Bylaw.Db.Check,
          Bylaw.Db.Issue,
          Bylaw.Db.Target
        ],
        "Bylaw.Db adapters": ~r/^(Elixir\.)?Bylaw\.Db\.Adapters\./,
        "Bylaw.Db checks": ~r/^(Elixir\.)?Bylaw\.Db\.Postgres\.Checks\./
      ],
      nest_modules_by_prefix: [
        Bylaw.Ecto.Query.Checks,
        Bylaw.Db.Postgres.Checks
      ]
    ]
  end
end
