defmodule HTMLParser.Parser do
  void = [
    "area",
    "base",
    "basefont",
    "br",
    "col",
    "command",
    "embed",
    "frame",
    "hr",
    "img",
    "input",
    "isindex",
    "keygen",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",

    # common self closing svg elements
    "path",
    "circle",
    "ellipse",
    "line",
    "rect",
    "use",
    "stop",
    "polyline",
    "polygon"
  ]

  def void?(el) when el in unquote(void), do: true
  def void?(_), do: false

  defp maybe_push_stack(%{stack: stack, xml: xml} = state, name)
  when xml or not name in unquote(void) do
    %{state | stack: [name | stack]}
  end
  defp maybe_push_stack(state, _) do
    state
  end

  form_tags = [
    "input",
    "option",
    "optgroup",
    "select",
    "button",
    "datalist",
    "textarea"
  ]

  implies_close = %{
  	"tr" => ["tr", "th", "td"],
  	"th" => ["th"],
  	"td" => ["thead", "th", "td"],
  	"body" => ["head", "link", "script"],
  	"li" => ["li"],
  	"p" => ["p"],
  	"h1" => ["p"],
  	"h2" => ["p"],
  	"h3" => ["p"],
  	"h4" => ["p"],
  	"h5" => ["p"],
  	"h6" => ["p"],
  	"select" => form_tags,
  	"input" => form_tags,
  	"output" => form_tags,
  	"button" => form_tags,
  	"datalist" => form_tags,
  	"textarea" => form_tags,
  	"option" => ["option"],
  	"optgroup" => ["optgroup"]
  }

  defp open_implies_close(%{xml: false} = state, name) when name in unquote(Map.keys(implies_close)) do
    # TODO
    {[], state}
  end
  defp open_implies_close(state, _) do
    {[], state}
  end

  def parse(tokens, opts \\ %{}) do
    state = %{
      xml: !!opts[:xml],
      decode_entities: !!opts[:decode_entities],
      cdata: !!opts[:cdata],
      downcase_tags: !!opts[:downcase_tags],
      downcase_attribute_names: !!opts[:downcase_attribute_names],
      self_closing: !!opts[:self_closing],
      tag_name: nil,
      attribute_name: nil,
      attribute_value: nil,
      attributes: %{},
      start_index: 0,
      end_index: 0,
      stack: [],
    }
    Stream.resource(
      fn -> {tokens, state} end,
      fn
        (nil) ->
          {:halt, nil}
        ({stream, state}) ->
          case Nile.Utils.next(stream) do
            {status, _stream} when status in [:done, :halted] ->
              {_, acc} = close_current_tag_names(state.stack, nil, [])
              {acc, nil}
            {:suspended, token, stream} ->
              {acc, state} = handle_token(token, state)
              {Enum.to_list(acc), {stream, state}}
          end
      end,
      fn(_) -> nil end
    )
  end

  defp handle_token({:text, _, _} = text, state) do
    {[text], state}
  end

  defp handle_token({:open_tag_name, info, name}, state) do
    name = maybe_downcase_tag(state, name)
    {tokens, state} = open_implies_close(state, name)
    state = maybe_push_stack(state, name)
    tokens = Stream.concat(tokens, [{:open_tag_name, info, name}])
    {tokens, %{state | tag_name: name, attributes: []}}
  end

  defp handle_token({:open_tag_end, info}, %{tag_name: name, attributes: attrs} = state) do
    open_tag = {:open_tag, info, name, :lists.reverse(attrs)}
    tokens = case state do
      %{xml: false} when name in unquote(void) ->
        [{:close_tag, info, name}, open_tag]
      _ ->
        [open_tag]
    end
    {tokens, %{state | tag_name: nil, attributes: []}}
  end

  defp handle_token({:close_tag, info, name}, state) do
    name = maybe_downcase_tag(state, name)
    case state do
      %{xml: xml, stack: stack} when not name in unquote(void) or xml ->
        {stack, closes} = close_current_tag_names(stack, name, [])
        {closes, %{state | stack: stack}}
      %{xml: false} when name in ["br", "p"] ->
        {opening, state} = handle_token({:open_tag_name, info, name}, state)
        {closing, state} = close_current_tag(state)
        {Stream.concat(opening, closing), state}
      _ ->
        {[], state}
    end
  end

  defp handle_token({:self_closing_tag, info}, %{xml: xml, self_closing: self_closing} = state) when xml or self_closing do
    close_current_tag(state)
  end
  defp handle_token({:self_closing_tag, info}, state) do
    handle_token({:open_tag_end, info}, state)
  end

  defp handle_token({:attribute_name, _info, name}, %{attribute_name: nil, downcase_attribute_names: dc} = state) do
    name = if dc, do: String.downcase(name), else: name
    {[], %{state | attribute_name: name}}
  end
  defp handle_token({:attribute_name, _info, name}, %{attribute_name: prev_name, downcase_attribute_names: dc, attributes: attrs} = state) do
    name = if dc, do: String.downcase(name), else: name
    attrs = [{prev_name, nil} | attrs]
    {[{:attribute, prev_name, nil}], %{state | attributes: attrs, attribute_name: name, attribute_value: nil}}
  end

  defp handle_token({:attribute_data, _info, value}, state) do
    {[], %{state | attribute_value: value}}
  end

  defp handle_token(:attribute_end, %{attribute_name: name, attribute_value: value, attributes: attrs} = state) do
    attrs = [{name, value} | attrs]
    {[{:attribute, name, value}], %{state | attributes: attrs, attribute_name: nil, attribute_value: nil}}
  end

  defp handle_token({:declaration, info, value}, state) do
    name = get_instruction_name(state, value)
    token = {:instruction, info, "!" <> name, "!" <> value}
    {[token], state}
  end

  defp handle_token({:processing_instruction, info, value}, state) do
    name = get_instruction_name(state, value)
    token = {:instruction, info, "?" <> name, "?" <> value}
    {[token], state}
  end

  defp handle_token({:comment, info, value}, state) do
    {[
      {:comment, info, value},
      :comment_end
    ], state}
  end

  defp handle_token({:cdata, info, value}, %{xml: xml, cdata: cdata} = state) when xml or cdata do
    {[
      :cdata_start,
      {:text, info, value},
      :cdata_end
    ], state}
  end
  defp handle_token({:cdata, value}, state) do
    {[{:comment, "[CDATA[" <> value <> "]]"}], state}
  end

  defp handle_token({:whitespace, _, _} = ws, state) do
    {[ws], state}
  end

  defp maybe_downcase_tag(%{downcase_tags: true}, name) do
    String.downcase(name)
  end
  defp maybe_downcase_tag(_, name) do
    name
  end

  defp close_current_tag(%{tag_name: tag, stack: stack} = state) do
    {ends, state} = handle_token(:open_tag_end, state)
    {stack, closes} = close_current_tag_names(stack, tag, [])
    {Stream.concat(ends, closes), %{state | stack: stack}}
  end

  defp close_current_tag_names([], _, acc) do
    {[], :lists.reverse(acc)}
  end
  defp close_current_tag_names([name | stack], name, acc) do
    {stack, :lists.reverse([{:close_tag, name} | acc])}
  end
  defp close_current_tag_names([s | stack], name, acc) do
    acc = [{:close_tag, s} | acc]
    close_current_tag_names(stack, name, acc)
  end

  @re_name_end ~r/\s|\//

  defp get_instruction_name(state, value) do
    name = case Regex.split(@re_name_end, value, parts: 2) do
      [name | _] -> name
      _ -> value
    end
    maybe_downcase_tag(state, name)
  end
end
