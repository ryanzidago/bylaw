defmodule Bylaw.MixProject do
  use Mix.Project

  def project do
    [
      app: :bylaw,
      version: "0.1.0",
      elixir: "~> 1.19",
      test_paths: test_paths(Mix.env()),
      dialyzer: dialyzer(),
      usage_rules: usage_rules(),
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.13", optional: true},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
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
end
