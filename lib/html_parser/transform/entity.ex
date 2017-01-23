defmodule HTMLParser.Transform.Entity do
  use HTMLParser.Transform
  alias HTMLParser.Entities, as: E

  def init(_) do
    %{
      type: :text
    }
  end

  def handle_token({:attribute_quote_open, _, _} = token, state) do
    {[token], %{state | type: :attribute_data}}
  end
  def handle_token({:tag_open_end, _} = token, state) do
    {[token], %{state | type: :text}}
  end

  def handle_token({:entity, line, {:named, code}}, %{type: type} = state) do
    token = case E.parse(code) do
      {:ok, char} ->
        {type, line, char}
      :error ->
        {type, line, "&" <> code}
    end
    {[token], state}
  end
  def handle_token({:entity, line, {:numeric, "#" <> code}}, %{type: type} = state) do
    {int, _} = Integer.parse(code, 10)
    {[{type, line, decode(int)}], state}
  end
  def handle_token({:entity, line, {:hex, "#" <> <<_>> <> code}}, %{type: type} = state) do
    {int, _} = Integer.parse(code, 16)
    {[{type, line, decode(int)}], state}
  end

  def handle_token(token, state) do
    {[token], state}
  end

  windows_1252 = %{
    128 => "\u20AC",
    130 => "\u201A",
    131 => "\u0192",
    132 => "\u201E",
    133 => "\u2026",
    134 => "\u2020",
    135 => "\u2021",
    136 => "\u02C6",
    137 => "\u2030",
    138 => "\u0160",
    139 => "\u2039",
    140 => "\u0152",
    142 => "\u017D",
    145 => "\u2018",
    146 => "\u2019",
    147 => "\u201C",
    148 => "\u201D",
    149 => "\u2022",
    150 => "\u2013",
    151 => "\u2014",
    152 => "\u02DC",
    153 => "\u2122",
    154 => "\u0161",
    155 => "\u203A",
    156 => "\u0153",
    158 => "\u017E",
    159 => "\u0178"
  }

  for {int, unicode} <- windows_1252 do
    defp decode(unquote(int)), do: unquote(unicode)
  end
  defp decode(0), do: "\uFFFD"
  defp decode(55296), do: "\uFFFD" # RESERVED CODE POINT
  defp decode(int) do
    <<int :: utf8>>
  rescue
    ArgumentError ->
      "\uFFFD"
  end
end