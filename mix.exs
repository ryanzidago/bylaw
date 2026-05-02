defmodule Bylaw.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ryanzidago/bylaw"

  def project do
    [
      app: :bylaw,
      version: @version,
      elixir: "~> 1.19",
      test_paths: test_paths(Mix.env()),
      dialyzer: dialyzer(),
      usage_rules: usage_rules(),
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/bylaw",
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

  defp test_paths(:test), do: ["lib"]
  defp test_paths(_env), do: ["test"]

  def cli do
    [
      preferred_envs: [
        qa: :test,
        dialyzer: :test
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.13"},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14.1", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit, :mix],
      plt_local_path: "priv/plts"
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [{:usage_rules, sub_rules: ["otp"]}]
    ]
  end

  defp docs do
    [
      main: "checks",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/checks.md": [title: "Checks"]
      ],
      groups_for_extras: [
        Guides: ~r/guides\//
      ],
      groups_for_modules: [
        Core: [
          Bylaw,
          Bylaw.Ecto.Query.Check,
          Bylaw.Ecto.Query.Issue
        ],
        "Ecto query checks": ~r/^Elixir\.Bylaw\.Ecto\.Query\.Checks(\.|$)/,
        "Mix tasks": ~r/^Elixir\.Mix\.Tasks\./
      ],
      nest_modules_by_prefix: [
        Bylaw.Ecto.Query.Checks
      ]
    ]
  end
end
