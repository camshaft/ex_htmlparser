defmodule HTMLParser.Transform.Entity do
  use HTMLParser.Transform

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

  def handle_token({:entity, line, {:known, _code, value}}, %{type: type} = state) do
    {[{type, line, value}], state}
  end
  def handle_token({:entity, line, {:named, name}}, %{type: type} = state) do
    token = case HTMLParser.Entities.parse(name) do
      {_, char, ""} ->
        {type, line, char}
      _ ->
        {type, line, "&" <> name}
    end
    {[token], state}
  end
  def handle_token({:entity, line, {:numeric, "#" <> code}}, %{type: type} = state) do
    {[{type, line, decode(parse(code, 10))}], state}
  end
  def handle_token({:entity, line, {:hex, "#" <> <<_>> <> code}}, %{type: type} = state) do
    {[{type, line, decode(parse(code, 16))}], state}
  end

  def handle_token(token, state) do
    {[token], state}
  end

  defp parse("0" <> rest, base) do
    parse(rest, base)
  end
  # 22 bytes == 2^65 bits + ";"
  defp parse(bin, _) when bin in ["", ";"] or byte_size(bin) >= 22 do
    0
  end
  defp parse(bin, base) do
    {int, _} = Integer.parse(bin, base)
    int
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
