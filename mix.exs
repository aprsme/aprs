defmodule Aprs.MixProject do
  use Mix.Project

  @source_url "https://github.com/gmcintire/aprs"
  @version "0.1.4"

  def project do
    [
      app: :aprs,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers(),
      deps: deps(),
      description: "APRS packet parser for Elixir (aprs)",
      package: package(),
      docs: docs(),
      source_url: @source_url
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
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:stream_data, "~> 1.2.0", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.1", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:styler, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Graham McIntire"],
      licenses: ["GPL-2.0"],
      links: %{
        "GitHub" => @source_url,
        "HexDocs" => "https://hexdocs.pm/aprs"
      },
      files: ["lib", "mix.exs", "README.md"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
