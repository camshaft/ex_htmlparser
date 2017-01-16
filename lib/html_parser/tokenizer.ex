defmodule HTMLParser.Tokenizer do
  import HTMLParser.Tokenizer.Macros

  defstruct [
    xml: false,
    decode_entities: false
  ]

  @whitespace [" ", "\r\n", "\n", "\t", "\f", "\r"]
  @numeric ?0..?9 |> Enum.map(&to_string/1)
  @hex [?a..?f |> Enum.map(&to_string/1),
        ?A..?F |> Enum.map(&to_string/1),
        @numeric] |> :lists.flatten()
  @alphanumeric [?a..?z |> Enum.map(&to_string/1),
                 ?A..?Z |> Enum.map(&to_string/1),
                 @numeric] |> :lists.flatten()

  def tokenize(stream, opts \\ %{})
  def tokenize(xml, opts) when is_binary(xml) do
    [xml]
    |> tokenize(opts)
  end
  def tokenize(stream, opts) do
    state = %{
      xml: !!opts[:xml],
      decode_entities: !!opts[:decode_entities],
      state: :text,
      buffer: "",
      section: [],
      base_state: :text,
      special: :none,
      tokens: [],
      whitespace: [],
      line: 1
    }
    Stream.resource(
      fn -> {stream, state} end,
      fn
        (nil) ->
          {:halt, nil}
        ({stream, %{buffer: buffer} = state}) ->
          case Nile.Utils.next(stream) do
            {status, _stream} when status in [:done, :halted] ->
              {[], nil}
            {:suspended, chunk, stream} ->
              buffer = :erlang.iolist_to_binary([buffer, chunk])
              %{tokens: tokens} = state = iterate(%{state | buffer: buffer, tokens: []})
              {:lists.reverse(tokens), {stream, state}}
          end
      end,
      fn(_) -> nil end
    )
  end

  for token <- @whitespace -- [" "] do
    defp iterate(%{state: s, buffer: unquote(token) <> buffer, whitespace: ws, line: l} = state) do
      {next_s, state} = tokenize(s, unquote(token), %{state | buffer: buffer, whitespace: [unquote(token) | ws]})
      %{state | state: next_s, line: l + 1}
      |> iterate()
    end
  end
  defp iterate(%{state: s, buffer: buffer, whitespace: ws} = state) do
    case String.next_grapheme(buffer) do
      {char, buffer} when char in @whitespace ->
        {next_s, state} = tokenize(s, char, %{state | buffer: buffer, whitespace: [char | ws]})
        %{state | state: next_s}
        |> iterate()
      {char, buffer} ->
        {next_s, state} = tokenize(s, char, %{state | buffer: buffer})
        %{state | state: next_s}
        |> iterate()
      _ ->
        cleanup(state)
    end
  end

  defp tokenize(:text, "<", state) do
    {:before_tag_name, emit_text(state)}
  end
  defp tokenize(:text, "&", %{decode_entities: true, special: :none} = state) do
    state = %{emit_text(state) | base_state: :text}
    {:before_entity, state}
  end

  defp tokenize(:before_tag_name, "/", state) do
    {:before_closing_tag_name, state}
  end
  defp tokenize(:before_tag_name, "<", state) do
    {:before_tag_name, emit_text(state)}
  end
  defp tokenize(:before_tag_name, c, %{section: s} = state) when c in unquote([">" | @whitespace]) do
    {:text, %{state | section: [c | s]}}
  end
  defp tokenize(:before_tag_name, c, %{section: s, special: special} = state) when special != :none do
    {:text, %{state | section: [c | s]}}
  end
  defp tokenize(:before_tag_name, "!", state) do
    {:before_declaration, %{state | section: []}}
  end
  defp tokenize(:before_tag_name, "?", state) do
    {:in_processing_instruction, %{state | section: []}}
  end
  defp tokenize(:before_tag_name, c, %{xml: false} = state) when c in ["s", "S"] do
    {:before_special, %{state | section: [c]}}
  end
  defp tokenize(:before_tag_name, c, state) do
    {:in_tag_name, %{state | section: [c]}}
  end

  defp tokenize(:in_tag_name, c, %{buffer: buffer} = state) when c in ["/", ">"] do
    state = emit_token_ss(state, :open_tag_name)
    {:before_attribute_name, %{state | buffer: c <> buffer}}
  end
  defp tokenize(:in_tag_name, c, %{buffer: buffer, whitespace: ws} = state) when c in @whitespace do
    state = emit_token_ss(%{state | whitespace: tl(ws)}, :open_tag_name)
    {:before_attribute_name, %{state | buffer: c <> buffer}}
  end

  defp tokenize(:before_closing_tag_name, c, state) when c in @whitespace do
    {:before_closing_tag_name, state}
  end
  defp tokenize(:before_closing_tag_name, ">" = c, %{section: section} = state) do
    {:text, %{state | section: [c | section]}}
  end
  defp tokenize(:before_closing_tag_name, c, %{special: special} = state) when c in ["s", "S"] and special != :none do
    {:before_special_end, %{state | section: [c]}}
  end
  defp tokenize(:before_closing_tag_name, c, %{buffer: buffer, special: special} = state) when special != :none do
    {:text, %{state | buffer: c <> buffer}}
  end
  defp tokenize(:before_closing_tag_name, c, state) do
    {:in_closing_tag_name, %{state | section: [c]}}
  end

  defp tokenize(:in_closing_tag_name, ">", %{buffer: b} = state) do
    state = emit_token_ss(state, :close_tag)
    {:after_closing_tag_name, %{state | buffer: ">" <> b}}
  end
  defp tokenize(:in_closing_tag_name, c, %{buffer: b, whitespace: ws} = state) when c in @whitespace do
    state = emit_token_ss(%{state | whitespace: tl(ws)}, :close_tag)
    {:after_closing_tag_name, %{state | buffer: c <> b}}
  end

  defp tokenize(:after_closing_tag_name, ">", state) do
    {:text, %{state | section: [], whitespace: []}}
  end

  defp tokenize(:before_attribute_name, ">", state) do
    state = emit_token(state, :open_tag_end)
    {:text, %{state | section: []}}
  end
  defp tokenize(:before_attribute_name, "/", state) do
    {:in_self_closing_tag, state}
  end
  defp tokenize(:before_attribute_name, c, state) when not c in @whitespace do
    {:in_attribute_name, %{state | section: [c]}}
  end

  defp tokenize(:in_self_closing_tag, ">", state) do
    state = emit_token(state, :self_closing_tag)
    {:text, %{state | section: []}}
  end
  defp tokenize(:in_self_closing_tag, c, %{buffer: b} = state) when not c in @whitespace do
    {:before_attribute_name, %{state | buffer: c <> b}}
  end

  defp tokenize(:in_attribute_name, c, %{buffer: b} = state)
  when c in unquote(["=", "/", ">" | @whitespace]) do
    state = emit_token_ss(state, :attribute_name)
    {:after_attribute_name, %{state | buffer: c <> b}}
  end

  defp tokenize(:after_attribute_name, "=", state) do
    {:before_attribute_value, emit_whitespace(state)}
  end
  defp tokenize(:after_attribute_name, c, %{buffer: b} = state) when c in ["/", ">"] do
    state = emit_token(state, :attribute_end)
    {:before_attribute_name, %{state | buffer: c <> b}}
  end
  defp tokenize(:after_attribute_name, c, state) when not c in @whitespace do
    {:in_attribute_name, %{state | section: [c]}}
  end

  defp tokenize(:before_attribute_value, "\"", state) do
    state = emit_token(state, :attribute_dq_open)
    {:in_attribute_value_dq, %{state | section: []}}
  end
  defp tokenize(:before_attribute_value, "'", state) do
    state = emit_token(state, :attribute_sq_open)
    {:in_attribute_value_sq, %{state | section: []}}
  end
  defp tokenize(:before_attribute_value, c, %{buffer: b} = state) when not c in @whitespace do
    state = emit_token(state, :attribute_nq_open)
    {:in_attribute_value_nq, %{state | section: [], buffer: c <> b}}
  end

  defp tokenize(:in_attribute_value_dq, "\"", state) do
    state = emit_token_ss(state, :attribute_data)
    state = emit_token(state, :attribute_dq_end)
    state = emit_token(state, :attribute_end)
    {:before_attribute_name, state}
  end

  defp tokenize(:in_attribute_value_sq, "'", state) do
    state = emit_token_ss(state, :attribute_data)
    state = emit_token(state, :attribute_sq_end)
    state = emit_token(state, :attribute_end)
    {:before_attribute_name, state}
  end

  defp tokenize(:in_attribute_value_nq, c, %{buffer: b} = state) when c in unquote([">" | @whitespace]) do
    state = emit_token_ss(state, :attribute_data)
    state = emit_token(state, :attribute_nq_end)
    state = emit_token(state, :attribute_end)
    {:before_attribute_name, %{state | buffer: c <> b}}
  end

  defp tokenize(s, "&", %{decode_entities: true} = state)
  when s in [:in_attribute_value_dq, :in_attribute_value_sq, :in_attribute_value_nq] do
    state = emit_token_ss(state, :attribute_data)
    state = %{state | base_state: s, section: []}
    {:before_entity, state}
  end

  defp tokenize(:before_declaration, "[", state) do
    {:before_cdata_1, state}
  end
  defp tokenize(:before_declaration, "-", state) do
    {:before_comment, state}
  end
  defp tokenize(:before_declaration, c, %{section: s} = state) do
    {:in_declaration, %{state | section: [c | s]}}
  end

  defp tokenize(:in_declaration, ">", state) do
    {:text, emit_token_ss(state, :declaration)}
  end

  defp tokenize(:in_processing_instruction, ">", state) do
    {:text, emit_token_ss(state, :processing_instruction)}
  end

  defp tokenize(:before_comment, "-", state) do
    {:in_comment, %{state | section: []}}
  end
  defp tokenize(:before_comment, _, state) do
    {:in_declaration, state}
  end

  defp tokenize(:in_comment, "-", state) do
    {:after_comment_1, state}
  end

  defp tokenize(:after_comment_1, "-", state) do
    {:after_comment_2, state}
  end
  defp tokenize(:after_comment_1, _, state) do
    {:in_comment, state}
  end

  defp tokenize(:after_comment_2, ">", state) do
    {:text, emit_token_ss(state, :comment)}
  end
  defp tokenize(:after_comment_2, c, %{section: s} = state) when c != "-" do
    {:in_comment, %{state | section: [c | s]}}
  end

  for {char, i} <- Stream.with_index('CDATA') do
    if_else_state(:"before_cdata_#{i}", char, :"before_cdata_#{i + 1}", :in_declaration)
  end
  defp tokenize(:before_cdata_6, "[", state) do
    {:in_cdata, %{state | section: []}}
  end
  defp tokenize(:before_cdata_6, c, %{buffer: b} = state) do
    {:in_declaration, %{state | buffer: c <> b}}
  end

  defp tokenize(:in_cdata, "]", state) do
    {:after_cdata_1, state}
  end

  defp tokenize(:after_cdata_1, "]", state) do
    {:after_cdata_2, state}
  end

  defp tokenize(:after_cdata_2, ">", state) do
    {:text, emit_token_ss(state, :cdata)}
  end
  defp tokenize(:after_cdata_2, c, %{section: s} = state) when c != "]" do
    {:in_cdata, %{state | section: [c | s]}}
  end

  defp tokenize(:before_special, c, %{section: s} = state) when c in ["c", "C"] do
    {:before_script_1, %{state | section: [c | s]}}
  end
  defp tokenize(:before_special, c, %{section: s} = state) when c in ["t", "T"] do
    {:before_style_1, %{state | section: [c | s]}}
  end
  defp tokenize(:before_special, c, %{buffer: b} = state) do
    {:in_tag_name, %{state | buffer: c <> b}}
  end

  defp tokenize(:before_special_end, c, %{section: s, special: :script} = state) when c in ["c", "C"] do
    {:after_script_1, %{state | section: [c | s]}}
  end
  defp tokenize(:before_special_end, c, %{section: s, special: :style} = state) when c in ["t", "T"] do
    {:after_style_1, %{state | section: [c | s]}}
  end
  defp tokenize(:before_special_end, c, %{buffer: b} = state) do
    {:text, %{state | buffer: c <> b}}
  end

  for <<_, rest :: binary>> = special <- ["script", "style"] do
    size = byte_size(rest)
    for {char, i} <- rest |> String.upcase |> to_charlist() |> Stream.with_index do
      if_else_state(:"before_#{special}_#{i}", char, :"before_#{special}_#{i + 1}", :in_tag_name)
      if_else_state(:"after_#{special}_#{i}", char, :"after_#{special}_#{i + 1}", :text)
    end
    defp tokenize(unquote(:"before_#{special}_#{size}"), c, %{buffer: b} = state) when c in unquote(["/", ">" | @whitespace]) do
      {:in_tag_name, %{state | buffer: c <> b, special: unquote(String.to_atom(special))}}
    end
    defp tokenize(unquote(:"before_#{special}_#{size}"), c, %{buffer: b} = state) do
      {:in_tag_name, %{state | buffer: c <> b}}
    end
    defp tokenize(unquote(:"after_#{special}_#{size}"), c, %{buffer: b} = state) when c in unquote([">" | @whitespace]) do
      {:in_closing_tag_name, %{state | special: :none, buffer: c <> b}}
    end
    defp tokenize(unquote(:"after_#{special}_#{size}"), c, %{buffer: b} = state) do
      {:text, %{state | buffer: c <> b}}
    end
  end

  if_else_state(:before_entity, ?#, :before_numeric_entity, :in_named_entity)
  if_else_state(:before_numeric_entity, ?X, :in_hex_entity, :in_numeric_entity)

  defp tokenize(:in_named_entity, _, ?;, %{base_state: base} = state) do
    state = parse_entity_strict(state)
    state = case state do
      %{section_start: ss, index: i, xml: false} when ss + 1 < i ->
        parse_entity_legacy(state)
      _ ->
        state
    end
    {base, state}
  end
  defp tokenize(:in_named_entity, i, c, %{xml: true, base_state: base} = state) when not c in @alphanumeric do
    {base, %{state | index: i - 1}}
  end
  defp tokenize(:in_named_entity, i, _, %{section_start: ss, base_state: base} = state) when ss + 1 == i do
    {base, %{state | index: i - 1}}
  end
  defp tokenize(:in_named_entity, i, ?=, %{base_state: base} = state) when base != :text do
    state = parse_entity_strict(state)
    {base, %{state | index: i - 1}}
  end
  defp tokenize(:in_named_entity, i, _, %{base_state: base} = state) when base != :text do
    {base, %{state | index: i - 1}}
  end
  defp tokenize(:in_named_entity, i, _, %{base_state: base} = state) do
    state = parse_entity_legacy(state)
    {base, %{state | index: i - 1}}
  end

  defp tokenize(:in_numeric_entity, _, ?;, state) do
    {s, %{section_start: ss} = state} = parse_entity_numeric(state, 2, 10)
    {s, %{state | section_start: ss + 1}}
  end
  defp tokenize(:in_numeric_entity, _, c, %{xml: false} = state) when not c in @numeric do
    {s, %{index: i} = state} = parse_entity_numeric(state, 2, 10)
    {s, %{state | index: i - 1}}
  end
  defp tokenize(:in_numeric_entity, i, c, %{base_state: base} = state) when not c in @numeric do
    {base, %{state | index: i - 1}}
  end

  defp tokenize(:in_hex_entity, _, ?;, state) do
    {s, %{section_start: ss} = state} = parse_entity_numeric(state, 3, 16)
    {s, %{state | section_start: ss + 1}}
  end
  defp tokenize(:in_hex_entity, _, c, %{xml: false} = state) when not c in @hex do
    {s, %{index: i} = state} = parse_entity_numeric(state, 3, 16)
    {s, %{state | index: i - 1}}
  end
  defp tokenize(:in_hex_entity, i, c, %{base_state: base} = state) when not c in @hex do
    {base, %{state | index: i - 1}}
  end

  # catchall
  defp tokenize(s, char, %{section: section} = state) do
    {s, %{state | section: [char | section]}}
  end

  defp cleanup(state) do
    state
  end

  defp parse_entity_strict(state) do
    # TODO
    state
  end

  defp parse_entity_legacy(state) do
    # TODO
    state
  end

  defp parse_entity_numeric(state, offset, base) do
    # TODO
    state
  end

  defp emit_text(%{section: []} = state) do
    state
  end
  defp emit_text(state) do
    %{state | whitespace: []}
    |> emit_token_ss(:text)
  end
end
