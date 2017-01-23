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
    |> Enum.sort(fn({a, _}, {b, _}) ->
      a = String.trim_trailing(a, ";")
      b = String.trim_trailing(b, ";")
      cond do
        byte_size(a) == byte_size(b) ->
          case {String.downcase(a), String.downcase(b)} do
            {d, d} ->
              a <= b
            {a, b} ->
              a <= b
          end
        true ->
          byte_size(a) >= byte_size(b)
      end
    end)
    |> Stream.map(fn({key, %{"codepoints" => points}}) ->
      char = :unicode.characters_to_binary(points)
      :io_lib.format('parse(~p)->{ok,~p};~n', [key, char])
    end)
    |> Enum.join(),
  "parse(_) -> error.\n"
]

File.mkdir_p!("src")
File.write!("src/Elixir.HTMLParser.Entities.erl", module)
