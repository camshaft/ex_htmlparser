defmodule HTMLParser.Transform.Attribute do
  use HTMLParser.Transform

  def init(opts) do
    %{
      downcase: Access.get(opts, :downcase, true),
      default_value: Access.get(opts, :default_value, ""),
      name: nil,
      value: [],
    }
  end

  def handle_token({:attribute_name, line, name}, %{name: nil, downcase: dc} = state) do
    name = if dc, do: String.downcase(name), else: name
    {[{:attribute_name, line, name}], %{state | name: name}}
  end
  def handle_token({:attribute_name, line, name}, %{name: _, downcase: dc, default_value: value} = state) do
    name = if dc, do: String.downcase(name), else: name
    tokens = [
      {:attribute_value, line, value},
      # TODO handle quote end
      {:attribute_name, line, name}
    ]
    {tokens, %{state | name: name, value: []}}
  end

  def handle_token({:attribute_data, _line, value}, %{value: prev} = state) do
    {[], %{state | value: [prev | value]}}
  end

  def handle_token({:attribute_quote_close, line, _} = t, %{value: value} = state) do
    tokens = [
      {:attribute_value, line, :erlang.iolist_to_binary(value)},
      t
    ]
    {tokens, %{state | name: nil, value: []}}
  end

  def handle_token(other, state) do
    {[other], state}
  end
end
