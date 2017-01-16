defmodule HTMLParser do
  def to_dom(input, opts \\ %{}) do
    input
    |> tokenize(opts)
    |> __MODULE__.DOM.collect(opts)
  end

  def tokenize(input, opts \\ %{}) do
    input
    |> __MODULE__.Tokenizer.tokenize(opts)
    |> __MODULE__.Parser.parse(opts)
  end
end
