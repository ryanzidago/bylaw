defmodule Bylaw.MixProject do
  use Mix.Project

  def project do
    [
      app: :bylaw,
      version: "0.1.0",
      elixir: "~> 1.19",
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:usage_rules, "~> 1.2", only: :dev, runtime: false}
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [{:usage_rules, sub_rules: ["otp"]}]
    ]
  end
end
