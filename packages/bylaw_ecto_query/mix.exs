defmodule BylawEctoQuery.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ryanzidago/bylaw"

  def project do
    [
      app: :bylaw_ecto_query,
      version: @version,
      elixir: "~> 1.19",
      test_paths: test_paths(Mix.env()),
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/bylaw_ecto_query",
      description: "Ecto query validation APIs and checks for Bylaw.",
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :bylaw]
    ]
  end

  defp test_paths(:test), do: ["lib"]
  defp test_paths(_env), do: ["test"]

  defp deps do
    [
      {:bylaw, "~> 0.1", hex: :bylaw, path: "../bylaw"},
      {:ecto, "~> 3.13"},
      {:ex_doc, "~> 0.39", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: :dev, runtime: false}
    ]
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
      main: "ecto_query_checks",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/ecto_query_checks.md": [title: "Bylaw.Ecto.Query Checks"]
      ],
      groups_for_modules: [
        "Bylaw.Ecto.Query": [
          Bylaw.Ecto.Query,
          Bylaw.Ecto.Query.Check,
          Bylaw.Ecto.Query.Checks,
          Bylaw.Ecto.Query.Issue
        ],
        "Bylaw.Ecto.Query checks": ~r/^(Elixir\.)?Bylaw\.Ecto\.Query\.Checks\./
      ],
      nest_modules_by_prefix: [Bylaw.Ecto.Query.Checks]
    ]
  end
end
