defmodule Test.Htmlparser do
  use ExUnit.Case

  for file <- Path.wildcard(__DIR__ <> "/documents/*") do
    name = Path.basename(file)
    test "#{name} - round trip" do
      out = unquote(file)
      |> File.stream!()
      |> HTMLParser.Tokenizer.tokenize()
      |> HTMLParser.Parser.parse()
      |> HTMLParser.DOM.collect()
      |> to_string()

      assert out == File.read!(unquote(file))
    end
  end
end
