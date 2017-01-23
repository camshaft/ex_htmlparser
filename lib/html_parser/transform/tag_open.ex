defmodule HTMLParser.Transform.TagOpen do
  use HTMLParser.Transform

  defmodule MapFirst do
    defstruct []

    defimpl Collectable do
      def into(_) do
        {%{}, fn
          map, {:cont, {k, v}} -> Map.put_new(map, k, v)
          map, :done -> map
          _, :halt -> :ok
        end}
      end
    end
  end

  def init(opts) do
    into = opts |> Access.get(:attributes_mode, :map) |> get_into()
    %{
      into: into,
      downcase: Access.get(opts, :downcase, true),
      name: nil,
      line: 1,
      attr_name: nil,
      attributes: into
    }
  end

  defp get_into(mode) when mode in [:map, :map_first] do
    %MapFirst{}
  end
  defp get_into(:map_last) do
    %{}
  end
  defp get_into(into) when is_map(into) or is_list(into) do
    into
  end

  def handle_token({:tag_open_name, line, name}, %{downcase: downcase, into: into} = state) do
    name = if downcase, do: String.downcase(name), else: name
    {[], %{state | attributes: into, line: line, name: name}}
  end
  def handle_token({:attribute_name, _line, name}, state) do
    {[], %{state | attr_name: name}}
  end
  def handle_token({:attribute_value, _line, value}, %{attributes: attributes, attr_name: name} = state) do
    attributes = Nile.Utils.put(attributes, {:cont, {name, value}})
    {[], %{state | attributes: attributes}}
  end

  def handle_token({name, _, _}, state)
  when name in [:attribute_quote_open, :attribute_quote_close] do
    {[], state}
  end

  def handle_token({:tag_open_end, _line}, %{name: name, line: line, attributes: attributes} = state) do
    {[{:tag_open, line, {name, Nile.Utils.put(attributes, :done)}}], state}
  end

  def handle_token({:tag_self_close, _line}, %{name: name, line: line, attributes: attributes} = state) do
    {[{:tag_open_close, line, {name, Nile.Utils.put(attributes, :done)}}], state}
  end

  def handle_token(other, state) do
    {[other], state}
  end
end
