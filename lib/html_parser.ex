defmodule HTMLParser do
  defmodule DOM.Error do
    defexception [:message, :line]
  end
  defmodule Parser.Error do
    defexception [:message, :line]
  end

  def parse(input, opts \\ %{}) do
    input
    |> scan(opts)
    |> parse_tokens(opts)
  end

  def parse!(input, opts \\ %{}) do
    input
    |> scan(opts)
    |> parse_tokens!(opts)
  end

  def parse_tokens(input, opts \\ %{}) do
    {:ok, parse_tokens!(input, opts)}
  rescue
    e in ParserError ->
      {:error, e.message}
  end

  def parse_tokens!(tokens, opts \\ %{})
  def parse_tokens!(tokens, _opts) do
    tokens
    # TODO add transform for dropping stuff we don't need
    |> Stream.filter(fn
      ({:whitespace, _, _}) ->
        false
      (_) ->
        true
    end)
    # TODO any way to make this stream-friendly?
    |> Enum.to_list()
    |> __MODULE__.Parser.parse()
    |> case do
      {:error, {line, _module, error}} ->
        raise Parser.Error, message: :erlang.iolist_to_binary(error), line: line
      {:ok, document} ->
        document
    end
  end

  def to_dom(input, opts \\ %{}) do
    input
    |> scan(opts)
    |> __MODULE__.DOM.collect(opts)
  end

  def scan(input, opts \\ %{}) do
    input
    |> __MODULE__.Tokenizer.scan(opts)
    |> __MODULE__.Transform.Entity.transform()
    |> __MODULE__.Transform.Attribute.transform()
    |> __MODULE__.Transform.TagOpen.transform()
    # |> __MODULE__.Transform.TagClose.transform()
    |> __MODULE__.Transform.MergeText.transform()
  end
end
