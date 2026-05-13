defmodule BylawHtml.MixProject do
  use Mix.Project

  @version "0.1.0-alpha.2"
  @source_url "https://github.com/ryanzidago/bylaw"

  def project do
    [
      app: :bylaw_html,
      version: @version,
      elixir: "~> 1.19",
      test_paths: test_paths(Mix.env()),
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/bylaw_html",
      description: "Validation checks for rendered HTML strings.",
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :bylaw_core]
    ]
  end

  defp test_paths(:test), do: ["lib"]
  defp test_paths(_env), do: ["test"]

  defp deps do
    [
      {:bylaw_core, "~> 0.1.0", hex: :bylaw_core, path: "../bylaw_core"},
      {:bylaw_credo, "== 0.1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.4"},
      {:lazy_html, "~> 0.1.11"},
      {:usage_rules, "~> 1.2", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files:
        Path.wildcard("lib/**/*.ex") ++
          ~w(.formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
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
        "Bylaw.HTML": [
          Bylaw.HTML,
          Bylaw.HTML.Check,
          Bylaw.HTML.Issue
        ],
        "Bylaw.HTML checks": ~r/^(Elixir\.)?Bylaw\.HTML\.Check\./
      ],
      nest_modules_by_prefix: [Bylaw.HTML.Check]
    ]
  end
end
