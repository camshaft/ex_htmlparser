defmodule HTMLParser.Tokenizer do
  import HTMLParser.Tokenizer.Macros

  defstruct [
    xml: false,
    tokenize_entites: false
  ]

  @newline ["\n", "\f"]
  @whitespace [" ", "\t" | @newline]
  @alpha [?a..?z |> Enum.map(&<<&1>>),
          ?A..?Z |> Enum.map(&<<&1>>)] |> :lists.flatten()
  @numeric ?0..?9 |> Enum.map(&<<&1>>)
  @hex [?a..?f |> Enum.map(&<<&1>>),
        ?A..?F |> Enum.map(&<<&1>>),
        @numeric] |> :lists.flatten()
  @alphanumeric [@alpha,
                 @numeric] |> :lists.flatten()

  def tokenize(stream, opts \\ %{})
  def tokenize(buffer, opts) when is_binary(buffer) do
    [buffer]
    |> tokenize(opts)
  end
  def tokenize(stream, opts) do
    xml? = !!opts[:xml]
    state = %{
      xml: xml?,
      tokenize_entites: Access.get(opts, :tokenize_entites, true),
      special_tags:
        opts
        |> Access.get(:special_tags, if(xml?, do: [], else: ["script", "style"]))
        |> Enum.into(MapSet.new()),
      state: :text,
      buffer: "",
      section: [],
      base_state: :text,
      special: nil,
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
              {_, %{tokens: tokens}} = tokenize(state.state, :EOS, %{state | tokens: []})
              {:lists.reverse(tokens), nil}
            {:suspended, chunk, stream} ->
              buffer = :erlang.iolist_to_binary([buffer, chunk])
              %{tokens: tokens} = state = iterate(%{state | buffer: buffer, tokens: []})
              {:lists.reverse(tokens), {stream, state}}
          end
      end,
      fn(_) -> nil end
    )
  end

  defp iterate(%{buffer: "\r\n" <> buffer} = state) do
    iterate(%{state | buffer: "\n" <> buffer})
  end
  defp iterate(%{buffer: "\r\0" <> buffer} = state) do
    iterate(%{state | buffer: "\n\0" <> buffer})
  end
  defp iterate(%{buffer: "\r" <> buffer} = state) do
    iterate(%{state | buffer: "\n" <> buffer})
  end
  for token <- @newline do
    defp iterate(%{state: s, buffer: unquote(token) <> buffer, whitespace: ws, line: l} = state) do
      {next_s, state} = tokenize(s, unquote(token), %{state | buffer: buffer, whitespace: [ws | unquote(token)]})
      %{state | state: next_s, line: l + 1}
      |> iterate()
    end
  end
  for token <- @whitespace -- @newline do
    defp iterate(%{state: s, buffer: unquote(token) <> buffer, whitespace: ws} = state) do
      {next_s, state} = tokenize(s, unquote(token), %{state | buffer: buffer, whitespace: [ws | unquote(token)]})
      %{state | state: next_s}
      |> iterate()
    end
  end
  defp iterate(%{state: s, buffer: buffer} = state) do
    case String.next_grapheme(buffer) do
      {char, buffer} ->
        {next_s, state} = tokenize(s, char, %{state | buffer: buffer})
        %{state | state: next_s}
        |> iterate()
      nil ->
        state
    end
  end

  defp tokenize(:text, "<", state) do
    {:before_tag_name, emit_text(state)}
  end
  defp tokenize(:text, "&", %{tokenize_entites: true, special: nil} = state) do
    state = %{emit_text(state) | base_state: :text}
    {:before_entity, state}
  end
  defp tokenize(:text, :EOS, %{section: section} = state) when section != [] do
    {:text, emit_text(state)}
  end

  defp tokenize(:before_tag_name, "/", state) do
    {:before_closing_tag_name, state}
  end
  defp tokenize(:before_tag_name, c, state) when c in ["<", :EOS] do
    {:before_tag_name, emit_text(%{state | section: "<"})}
  end
  defp tokenize(:before_tag_name, c, state) when c in unquote([">", "\0", "\v" | @whitespace]) do # TODO do we need more of these?
    {:text, %{state | section: "<" <> c}}
  end
  defp tokenize(:before_tag_name, c, %{section: s, special: special} = state) when not is_nil(special) do
    {:text, %{state | section: [s | c]}}
  end
  defp tokenize(:before_tag_name, "!", state) do
    {:before_declaration, %{state | section: []}}
  end
  defp tokenize(:before_tag_name, "?", state) do
    {:in_processing_instruction, %{state | section: []}}
  end
  defp tokenize(:before_tag_name, c, state) do
    {:in_tag_name, %{state | section: c}}
  end

  defp tokenize(:in_tag_name, c, state) when c in ["/", ">"] do
    # TODO check to see if it's a special tag
    state = emit_token_ss(state, :tag_open_name)
    tokenize(:before_attribute_name, c, state)
  end
  defp tokenize(:in_tag_name, :EOS, state) do
    {:in_tag_name, state}
  end
  defp tokenize(:in_tag_name, c, %{whitespace: ws} = state) when c in @whitespace do
    # TODO check to see if it's a special tag
    state = emit_token_ss(%{state | whitespace: hd(ws)}, :tag_open_name)
    tokenize(:before_attribute_name, c, state)
  end

  defp tokenize(:before_closing_tag_name, c, state) when c in @whitespace do
    {:before_closing_tag_name, state}
  end
  defp tokenize(:before_closing_tag_name, ">", %{section: []} = state) do
    {:text, state}
  end
  defp tokenize(:before_closing_tag_name, ">" = c, %{section: section} = state) do
    {:text, %{state | section: [section | c]}}
  end
  defp tokenize(:before_closing_tag_name, c, state) do
    {:in_closing_tag_name, %{state | section: c}}
  end

  defp tokenize(:in_closing_tag_name, ">", state) do
    # TODO check to see if it's a special tag
    state = emit_token_ss(state, :tag_close)
    tokenize(:after_closing_tag_name, ">", state)
  end
  defp tokenize(:in_closing_tag_name, c, %{whitespace: ws} = state) when c in @whitespace do
    # TODO check to see if it's a special tag
    state = emit_token_ss(%{state | whitespace: hd(ws)}, :tag_close)
    tokenize(:after_closing_tag_name, c, state)
  end

  defp tokenize(:after_closing_tag_name, ">", state) do
    {:text, %{state | section: [], whitespace: []}}
  end

  defp tokenize(:before_attribute_name, ">", state) do
    state = emit_token(state, :tag_open_end)
    {:text, %{state | section: []}}
  end
  defp tokenize(:before_attribute_name, "/", state) do
    {:in_self_closing_tag, state}
  end
  defp tokenize(:before_attribute_name, c, state) when not c in @whitespace do
    {:in_attribute_name, %{state | section: c}}
  end

  defp tokenize(:in_self_closing_tag, ">", state) do
    state = emit_token(state, :tag_self_close)
    {:text, %{state | section: []}}
  end
  defp tokenize(:in_self_closing_tag, c, state) when not c in @whitespace do
    tokenize(:before_attribute_name, c, state)
  end

  defp tokenize(:in_attribute_name, c, state)
  when c in unquote(["=", "/", ">" | @whitespace]) do
    state = emit_token_ss(state, :attribute_name)
    tokenize(:after_attribute_name, c, state)
  end

  defp tokenize(:after_attribute_name, "=", state) do
    {:before_attribute_value, emit_whitespace(state)}
  end
  defp tokenize(:after_attribute_name, c, %{tokens: tokens, line: line} = state) when c in ["/", ">"] do
    open = {:attribute_quote_open, line, ""}
    close = {:attribute_quote_close, line, ""}
    tokenize(:before_attribute_name, c, %{state | section: [], tokens: [close, open | tokens]})
  end
  defp tokenize(:after_attribute_name, c, state) when not c in @whitespace do
    {:in_attribute_name, %{state | section: c}}
  end

  defp tokenize(:before_attribute_value, "\"", state) do
    state = emit_token_ss(%{state | section: "\""}, :attribute_quote_open)
    {:in_attribute_value_dq, state}
  end
  defp tokenize(:before_attribute_value, "'", state) do
    state = emit_token_ss(%{state | section: "'"}, :attribute_quote_open)
    {:in_attribute_value_sq, state}
  end
  defp tokenize(:before_attribute_value, c, state) when not c in @whitespace do
    state = emit_token_ss(%{state | section: ""}, :attribute_quote_open)
    tokenize(:in_attribute_value_nq, c, state)
  end

  defp tokenize(:in_attribute_value_dq, "\"", state) do
    state = emit_token_ss(state, :attribute_data)
    state = emit_token_ss(%{state | section: "\""}, :attribute_quote_close)
    {:before_attribute_name, state}
  end

  defp tokenize(:in_attribute_value_sq, "'", state) do
    state = emit_token_ss(state, :attribute_data)
    state = emit_token_ss(%{state | section: "'"}, :attribute_quote_close)
    {:before_attribute_name, state}
  end

  defp tokenize(:in_attribute_value_nq, c, state) when c in unquote([">" | @whitespace]) do
    state = emit_token_ss(state, :attribute_data)
    state = emit_token_ss(%{state | section: ""}, :attribute_quote_close)
    tokenize(:before_attribute_name, c, state)
  end

  defp tokenize(s, "&", %{tokenize_entites: true} = state)
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
  defp tokenize(:before_declaration, "\0", state) do
    tokenize(:in_comment, "\0", state)
  end
  defp tokenize(:before_declaration, :EOS, state) do
    tokenize(:in_comment, :EOS, %{state | section: ""})
  end
  defp tokenize(:before_declaration, c, state) when c in @alpha do
    {:in_declaration, %{state | section: c}}
  end
  defp tokenize(:before_declaration, c, state) do
    {:in_comment, %{state | section: c}}
  end

  defp tokenize(:in_declaration, ">", state) do
    {:text, emit_token_ss(state, :declaration)}
  end
  defp tokenize(:in_declaration, :EOS, state) do
    {:text, emit_token_ss(state, :declaration)}
  end

  defp tokenize(:in_processing_instruction, ">", state) do
    {:text, emit_token_ss(state, :processing_instruction)}
  end
  defp tokenize(:in_processing_instruction, "\n", state) do
    tokenize(:in_comment, "\n", %{state | section: "?"})
  end
  defp tokenize(:in_processing_instruction, :EOS, state) do
    tokenize(:in_comment, :EOS, %{state | section: "?"})
  end

  defp tokenize(:before_comment, "-", state) do
    {:in_comment, %{state | section: []}}
  end
  defp tokenize(:before_comment, :EOS, state) do
    tokenize(:in_comment, :EOS, %{state | section: "-"})
  end
  defp tokenize(:before_comment, _, state) do
    {:in_declaration, state}
  end

  defp tokenize(:in_comment, "-", state) do
    {:after_comment_1, state}
  end
  defp tokenize(:in_comment, "\0", %{section: s} = state) do
    {:in_comment, %{state | section: [s | "\uFFFD"]}}
  end
  defp tokenize(:in_comment, :EOS, %{section: section} = state) when section != [] do
    {:text, emit_token_ss(state, :comment)}
  end
  defp tokenize(:in_comment, :EOS, state) do
    {:text, emit_token_ss(%{state | section: ""}, :comment)}
  end

  defp tokenize(:after_comment_1, "-", state) do
    {:after_comment_2, state}
  end
  defp tokenize(:after_comment_1, :EOS, state) do
    tokenize(:in_comment, :EOS, state)
  end
  defp tokenize(:after_comment_1, c, %{section: s} = state) do
    tokenize(:in_comment, c, %{state | section: [s | "-"]})
  end

  defp tokenize(:after_comment_2, ">", state) do
    {:text, emit_token_ss(state, :comment)}
  end
  defp tokenize(:after_comment_2, :EOS, state) do
    tokenize(:in_comment, :EOS, state)
  end
  defp tokenize(:after_comment_2, c, %{section: s} = state) when c != "-" do
    tokenize(:in_comment, c, %{state | section: [s | "--"]})
  end

  for {char, i} <- Stream.with_index('CDATA') do
    if_else_state(:"before_cdata_#{i}", char, :"before_cdata_#{i + 1}", :in_declaration)
  end
  defp tokenize(:before_cdata_6, "[", state) do
    {:in_cdata, %{state | section: []}}
  end
  defp tokenize(:before_cdata_6, c, state) do
    tokenize(:in_declaration, c, state)
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
    {:in_cdata, %{state | section: [s | c]}}
  end

  defp tokenize(:before_entity, c, %{base_state: base} = state) when c in unquote([";", :EOS | @whitespace]) do
    tokenize(base, c, %{state | section: "&"})
  end
  if_else_state(:before_entity, ?#, :before_numeric_entity, :in_named_entity)

  defp tokenize(:before_numeric_entity, c, %{base_state: base} = state) when c in unquote([";", :EOS | @whitespace]) do
    tokenize(base, c, %{state | section: "&#"})
  end
  if_else_state(:before_numeric_entity, ?X, :in_hex_entity, :in_numeric_entity)

  defp tokenize(:in_named_entity, :EOS, state) do
    {base, state} = tokenize_entity(state, :named, "", 1)
    tokenize(base, :EOS, state)
  end
  defp tokenize(:in_named_entity, c, %{base_state: :text, buffer: buffer, line: l, tokens: tokens, section: s} = state) do
    [s, c | buffer]
    |> :erlang.iolist_to_binary()
    |> HTMLParser.Entities.parse()
    |> case do
      {name, value, buffer} ->
        token = {:entity, l, {:known, name, value}}
        {:text, %{state | buffer: buffer, tokens: [token | tokens], section: []}}
      :error ->
        tokenize(:in_unknown_entity, c, state)
    end
  end
  defp tokenize(:in_named_entity, c, state) do
    tokenize(:in_unknown_entity, c, state)
  end

  defp tokenize(:in_unknown_entity, ";", state) do
    tokenize_entity(state, :named, ";", 1)
  end
  defp tokenize(:in_unknown_entity, "=", %{base_state: base} = state) when base != :text do
    tokenize_entity(state, :named, "=", 1)
  end
  defp tokenize(:in_unknown_entity, :EOS, state) do
    {base, state} = tokenize_entity(state, :named, "", 1)
    tokenize(base, :EOS, state)
  end

  for {state, {type, chars, min_length}} <- [in_hex_entity: {:hex, @hex, 3}, in_numeric_entity: {:numeric, @numeric, 2}] do
    defp tokenize(unquote(state), ";", state) do
      tokenize_entity(state, unquote(type), ";", unquote(min_length))
    end
    defp tokenize(unquote(state), :EOS, state) do
      {base, state} = tokenize_entity(state, unquote(type), "", unquote(min_length))
      tokenize(base, :EOS, state)
    end
    defp tokenize(unquote(state), c, %{buffer: buffer, xml: false} = state) when not c in unquote(chars) do
      tokenize_entity(%{state | buffer: c <> buffer}, unquote(type), "", unquote(min_length))
    end
    defp tokenize(unquote(state), c, %{base_state: base} = state) when not c in unquote(chars) do
      tokenize(base, c, state)
    end
  end

  # catchall
  defp tokenize(s, :EOS, %{section: []} = state) do
    {s, state}
  end
  defp tokenize(s, char, %{section: section} = state) when char != :EOS do
    {s, %{state | section: [section | char]}}
  end

  defp tokenize_entity(%{base_state: base, section: section, line: l, tokens: tokens} = state, type, suffix, min_length) do
    case :erlang.iolist_to_binary(section) do
      name when byte_size(name) >= min_length ->
        token = {:entity, l, {type, name <> suffix}}
        {base, %{state | tokens: [token | tokens], section: []}}
      section ->
        {base, %{state | section: "&" <> section <> suffix}}
    end
  end

  defp emit_text(%{section: []} = state) do
    state
  end
  defp emit_text(state) do
    %{state | whitespace: []}
    |> emit_token_ss(:text)
  end
end
