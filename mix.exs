defmodule HTMLParser.Mixfile do
  use Mix.Project

  def project do
    [app: :html_parser,
     version: "0.1.0",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     preferred_cli_env: [coveralls: :test, "coveralls.html": :test],
     test_coverage: [tool: ExCoveralls],
     deps: deps()]
  end

  def application do
    [applications: [:logger, :nile]]
  end

  defp deps do
    [{:nile, "~> 0.1.0"},
     {:mix_test_watch, "~> 0.2", only: :dev},
     {:poison, ">= 0.0.9", only: [:dev, :test]},
     {:httpoison, ">= 0.0.0", only: [:dev, :test]},
     {:excoveralls, "~> 0.5", only: :test},
     {:mochiweb_html, "~> 2.15", only: :test},
     {:exprof, "~> 0.2.0", only: [:dev, :test]},
     {:eministat, github: "jlouis/eministat", only: :test},
     {:html5lib_tests, github: "html5lib/html5lib-tests", app: false, compile: "exit 0", only: :test}]
  end
end
