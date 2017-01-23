defmodule HTMLParser.Transform.MergeText do
  use HTMLParser.Transform

  def init(_) do
    nil
  end

  for type <- [:text, :cdata, :comment] do
    def handle_token({unquote(type), line, data}, nil) do
      {[], {unquote(type), line, data}}
    end
    def handle_token({unquote(type), _line, data}, {unquote(type), line, prev}) do
      {[], {unquote(type), line, [prev | data]}}
    end
  end
  def handle_token(token, nil) do
    {[token], nil}
  end
  def handle_token(token, {type, line, data}) do
    {[{type, line, :erlang.iolist_to_binary(data)}, token], nil}
  end

  def handle_eos(nil) do
    []
  end
  def handle_eos({type, line, data}) do
    [{type, line, :erlang.iolist_to_binary(data)}]
  end
end
