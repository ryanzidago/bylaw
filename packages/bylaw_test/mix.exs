defmodule BylawTest.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ryanzidago/bylaw"

  def project do
    [
      app: :bylaw_test,
      version: @version,
      elixir: "~> 1.19",
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/bylaw_test",
      description:
        "ExUnit guards for Bylaw consumers, starting with unused database sandbox detection.",
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger, :ex_unit]]

  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:bylaw_credo, "== 0.4.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files:
        Path.wildcard("lib/**/*.ex") ++ ~w(.formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
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
        "Bylaw.Test": ~r/^(Elixir\.)?Bylaw\.Test/
      ]
    ]
  end
end
