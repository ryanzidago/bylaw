defmodule BylawCredo.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ryanzidago/bylaw"

  def project do
    [
      app: :bylaw_credo,
      version: @version,
      elixir: "~> 1.19",
      test_paths: test_paths(Mix.env()),
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/bylaw_credo",
      description: "Custom Credo checks for Bylaw.",
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

  defp test_paths(:test), do: ["lib"]
  defp test_paths(_env), do: ["test"]

  defp deps do
    [
      {:credo, "~> 1.7", runtime: false},
      {:ex_doc, "~> 0.39", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files:
        Path.wildcard("lib/**/*.ex") ++
          ~w(.credo.exs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
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
        "Bylaw.Credo checks": ~r/^(Elixir\.)?Bylaw\.Credo\.Check\./
      ],
      nest_modules_by_prefix: [Bylaw.Credo.Check]
    ]
  end
end
