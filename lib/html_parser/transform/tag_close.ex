defmodule HTMLParser.Transform.TagClose do
  # TODO
  use HTMLParser.Transform

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

  def init(opts \\ %{}) do
    %{
      xml: !!opts[:xml],
      decode_entities: !!opts[:decode_entities],
      cdata: !!opts[:cdata],
      downcase_tags: !!opts[:downcase_tags],
      downcase_attribute_names: !!opts[:downcase_attribute_names],
      self_closing: !!opts[:self_closing],
      tag_name: nil,
      attribute_name: nil,
      attribute_value: [],
      stack: [],
    }
  end

  def handle_token({:text, _, _} = text, state) do
    {[text], state}
  end

  def handle_token({:open_tag_name, line, name}, state) do
    name = maybe_downcase_tag(state, name)
    {tokens, state} = open_implies_close(state, name)
    state = maybe_push_stack(state, name)
    tokens = Stream.concat(tokens, [{:open_tag_name, line, name}])
    {tokens, %{state | tag_name: name}}
  end

  def handle_token({:open_tag_end, line} = token, %{tag_name: name} = state) do
    tokens = case state do
      %{xml: false} when name in unquote(void) ->
        # TODO save this until we know the next tag to see if they've put content
        #      in a void tag - even though they're not supposed to...
        [token, {:close_tag, line, name}]
      _ ->
        [token]
    end
    {tokens, %{state | tag_name: nil}}
  end

  def handle_token({:close_tag, line, name}, state) do
    name = maybe_downcase_tag(state, name)
    case state do
      %{xml: xml, stack: stack} when not name in unquote(void) or xml ->
        {stack, closes} = close_current_tag_names(stack, name, [])
        {closes, %{state | stack: stack}}
      %{xml: false} when name in ["br", "p"] ->
        {opening, state} = handle_token({:open_tag_name, line, name}, state)
        {closing, state} = close_current_tag(state)
        {Stream.concat(opening, closing), state}
      _ ->
        {[], state}
    end
  end

  def handle_token({:self_closing_tag, _line}, %{xml: xml, self_closing: self_closing} = state) when xml or self_closing do
    close_current_tag(state)
  end
  def handle_token({:self_closing_tag, line}, state) do
    handle_token({:open_tag_end, line}, state)
  end

  # Pass-through
  def handle_token({name, _, _} = token, state)
  when name in [:comment, :declaration, :processing_instruction, :whitespace] do
    {[token], state}
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
end
