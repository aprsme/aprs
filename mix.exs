defmodule Aprs.MixProject do
  use Mix.Project

  @source_url "https://github.com/aprsme/aprs"
  @version "2.0.2"

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
      # The mix tasks in lib/mix reference Mix, which is not in the default PLT.
      dialyzer: [plt_add_apps: [:mix]],
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
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:stream_data, "~> 1.4", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.4", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Graham McIntire"],
      licenses: ["GPL-3.0-or-later"],
      links: %{
        "GitHub" => @source_url,
        "HexDocs" => "https://hexdocs.pm/aprs"
      },
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"]
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
