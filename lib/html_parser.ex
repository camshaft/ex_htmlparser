defmodule HTMLParser do
  def to_dom(input, opts \\ %{}) do
    input
    |> tokenize(opts)
    |> __MODULE__.DOM.collect(opts)
  end

  def tokenize(input, opts \\ %{}) do
    input
    |> __MODULE__.Tokenizer.tokenize(put_in(opts, [:xml], false))
    |> __MODULE__.Transform.Entity.transform()
    |> __MODULE__.Transform.Attribute.transform()
    |> __MODULE__.Transform.TagOpen.transform()
    |> __MODULE__.Transform.MergeText.transform()
  end
end
