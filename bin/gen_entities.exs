Application.ensure_all_started(:httpoison)

source = "https://raw.githubusercontent.com/servo/html5ever/master/data/entities.json"

module = [
  "-module('Elixir.HTMLParser.Entities').\n",
  "-export([parse/1]).\n",
  source
    |> HTTPoison.get!()
    |> Map.get(:body)
    |> Poison.decode!()
    |> Stream.map(fn({"&" <> key, value}) ->
      {key, value}
    end)
    |> Stream.uniq(&elem(&1, 0))
    |> Enum.sort(fn
      ({a, _}, {b, _}) when byte_size(a) == byte_size(b) ->
        a <= b
      ({a, _}, {b, _}) ->
        byte_size(a) >= byte_size(b)
    end)
    |> Stream.map(fn({key, %{"codepoints" => points}}) ->
      match = :io_lib.format('~p', [key]) |> to_string() |> String.trim_trailing(">")
      char = :unicode.characters_to_binary(points)
      :io_lib.format('parse(~s,R/binary>>)->{~p,~p,R};~n', [match, key, char])
    end)
    |> Enum.join(),
  "parse(_) -> error.\n"
]

File.mkdir_p!("src")
File.write!("src/Elixir.HTMLParser.Entities.erl", module)
