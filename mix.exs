defmodule HTMLParser.Mixfile do
  use Mix.Project

  def project do
    [app: :html_parser,
     version: "0.1.0",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{:nile, "~> 0.1.0"},
     {:mix_test_watch, "~> 0.2", only: :dev},
     {:poison, "~> 3.0", only: :test}]
  end
end
