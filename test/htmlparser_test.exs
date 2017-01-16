defmodule Test.Htmlparser do
  use ExUnit.Case

  for file <- Path.wildcard(__DIR__ <> "/documents/*") do
    name = Path.basename(file)
    test "#{name} - round trip" do
      out = unquote(file)
      |> File.stream!()
      |> HTMLParser.to_dom()
      |> to_string()

      assert out == File.read!(unquote(file))
    end
  end

  convert_event = fn
    %{"event" => "opentagname", "data" => [name]} ->
      {:open_tag_name, name}
    %{"event" => "opentag", "data" => [name, attributes]} ->
      {:open_tag, name, Enum.to_list(attributes)}
    %{"event" => "closetag", "data" => [name]} ->
      {:close_tag, name}
    %{"event" => "attribute", "data" => [name, value]} ->
      {:attribute, name, value}
    %{"event" => "text", "data" => [data]} ->
      {:attribute, data}
    %{"event" => "cdatastart", "data" => []} ->
      :cdata_start
    %{"event" => "cdataend", "data" => []} ->
      :cdata_end
    %{"event" => "processinginstruction", "data" => [name, data]} ->
      {:processing_instruction, name, data}
    %{"event" => "comment", "data" => [data]} ->
      {:comment, data}
    %{"event" => "commentend", "data" => []} ->
      :comment_end
  end

  for file <- Path.wildcard(__DIR__ <> "/events/*") do
    name = Path.basename(file)
    test = Poison.decode!(File.read!(file))
    # TODO translate the options
    opts = test["options"]

    opts = Stream.concat(opts["handler"] || %{}, opts["parser"] || %{})
    |> Stream.flat_map(fn
      ({"lowerCaseTags", value}) ->
        [{:downcase_tags, value}]
      ({"xmlMode", value}) ->
        [{:xml, value}]
      ({"decodeEntities", value}) ->
        [{:decode_entities, value}]
      ({"recognizeCDATA", value}) ->
        [{:cdata, value}]
    end)
    |> Enum.into(%{})
    expected = Enum.map(test["expected"], convert_event)
    html = test["html"]

    test "#{test["name"]} | #{html}" do
      tokens = unquote(test["html"])
      |> HTMLParser.tokenize(unquote(Macro.escape(opts)))
      |> Enum.map(fn
        ({event, line}) when is_integer(line) ->
          event
        ({event, data}) ->
          # TODO these shouldn't happen
          {event, data}
        ({event, _line, data}) ->
          {event, data}
        ({event, _line, a, b}) ->
          {event, a, b}
      end)

      assert tokens == unquote(Macro.escape(expected))
    end
  end
end
