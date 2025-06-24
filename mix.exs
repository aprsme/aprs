defmodule AprsParser.MixProject do
  use Mix.Project

  def project do
    [
      app: :aprs,
      version: "0.1.2",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "APRS packet parser for Elixir (aprs)",
      package: package(),
      source_url: "https://github.com/gmcintire/aprs_parser"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:decimal, "~> 2.0"},
      {:stream_data, "~> 1.2.0", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.1", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:styler, "~> 1.4.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Graham McIntire"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/gmcintire/aprs_parser"},
      files: ["lib", "mix.exs", "README.md"]
    ]
  end
end
