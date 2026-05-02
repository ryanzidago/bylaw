defmodule Bylaw.MixProject do
  use Mix.Project

  def project do
    [
      app: :bylaw,
      version: "0.1.0",
      elixir: "~> 1.19",
      test_paths: test_paths(Mix.env()),
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
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false}
    ]
  end
end
