defmodule Test.HTMLParser.Bench do
  use Test.HTMLParser.Case

  @base "https://raw.githubusercontent.com/servo/html5ever/master/data/bench/"

  bench "lipsum-zh", 100, do: b("lipsum-zh")
  bench "lipsum", 100, do: b("lipsum")
  bench "tiny-fragment", 100, do: b("tiny-fragment")
  bench "small-fragment", 100, do: b("small-fragment")
  bench "medium-fragment", 100, do: b("medium-fragment")
  bench "strong", 100, do: b("strong")

  defp b(name) do
    Application.ensure_all_started(:httpoison)
    d = HTTPoison.get!(@base <> name <> ".html").body
    {
      fn ->
        :mochiweb_html.tokens(d)
      end,
      fn ->
        d
        |> HTMLParser.Tokenizer.scan()
        |> Enum.to_list()
      end
    }
  end
end
