defmodule BylawPostgres.MixProject do
  use Mix.Project

  @version "0.1.0-alpha.1"
  @source_url "https://github.com/ryanzidago/bylaw"

  def project do
    [
      app: :bylaw_postgres,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: test_paths(Mix.env()),
      aliases: aliases(),
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/bylaw_postgres",
      description: "Postgres database validation adapter and checks for Bylaw.",
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: ["test.postgres": :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp test_paths(:test), do: ["lib"]
  defp test_paths(_env), do: ["test"]

  defp aliases do
    [
      "test.postgres": [
        "ecto.drop --quiet --force",
        "ecto.create --quiet",
        "test --include postgres"
      ]
    ]
  end

  defp deps do
    [
      {:bylaw_core, "~> 0.1.0-alpha.1", hex: :bylaw_core, path: "../bylaw_core"},
      {:bylaw_credo, "== 0.1.0-alpha.1", only: [:dev, :test], runtime: false},
      {:bylaw_db, "~> 0.1.0-alpha.1", hex: :bylaw_db, path: "../bylaw_db"},
      {:ecto_sql, "~> 3.13"},
      {:ex_doc, "~> 0.39", only: [:dev, :test], runtime: false},
      {:postgrex, "~> 0.22.0"},
      {:usage_rules, "~> 1.2", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files:
        Path.wildcard("lib/**/*.ex") ++
          ~w(config .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"],
      groups_for_modules: [
        "Postgres adapter": [Bylaw.Db.Adapters.Postgres],
        "Postgres checks": ~r/^(Elixir\.)?Bylaw\.Db\.Adapters\.Postgres\.Checks\./,
        "Ecto helpers": ~r/^(Elixir\.)?Bylaw\.Ecto\./
      ],
      nest_modules_by_prefix: [Bylaw.Db.Adapters.Postgres.Checks]
    ]
  end
end
