defmodule Test.HTMLParser.HTML5Lib.Tokenizer do
  use ExUnit.Case, async: true

  defmodule CharacterJoin do
    use HTMLParser.Transform

    def init(_) do
      nil
    end

    def handle_token({"Character", char}, nil) do
      {[], char}
    end
    def handle_token({"Character", char}, acc) do
      {[], [acc, char]}
    end
    def handle_token(token, nil) do
      {[token], nil}
    end
    def handle_token(token, acc) do
      {[{"Character", :erlang.iolist_to_binary(acc)}, token], nil}
    end

    def handle_eos(nil) do
      []
    end
    def handle_eos(acc) do
      [{"Character", :erlang.iolist_to_binary(acc)}]
    end
  end

  Mix.Project.deps_paths[:html5lib_tests]
  |> Path.join("tokenizer/*.test")
  |> Path.wildcard()
  |> Stream.map(&{
    &1 |> Path.basename(".test") |> Macro.underscore(),
    &1 |> File.read!() |> Poison.decode!()
  })
  |> Enum.each(fn({name, tests}) ->
    tests = tests["tests"] || [] # tests["xmlViolationTests"] <- These are mean :(
    @tag name |> String.to_atom()
    test name do
      unquote(Macro.escape(tests))
      |> Stream.flat_map(&exec/1)
      |> Enum.to_list()
      |> case do
        [] ->
          true
        errors ->
          raise ExUnit.MultiError, errors: errors
      end
    end
  end)

  defp exec(%{"lastStartTag" => _}) do
    []
  end
  defp exec(%{"doubleEscaped" => _}) do
    # TODO
    []
  end
  defp exec(%{"input" => input, "output" => expected, "description" => message}) do
    expected = format_expected(expected)
    actual = format_actual(input)

    if expected == actual do
      []
    else
      [{:error, %ExUnit.AssertionError{
        message: message,
        left: expected,
        right: actual,
        expr: inspect(input)
       }, []}]
    end
  rescue
    err ->
      stack = System.stacktrace()
      [{:error, %ExUnit.AssertionError{
        message: message,
        left: format_expected(expected),
        right: Exception.format_banner(:error, err),
        expr: inspect(input)
       }, stack}]
  end

  defp format_expected(expected) do
    expected
    |> Stream.filter(&(&1 != "ParseError"))
    |> Stream.map(&:erlang.list_to_tuple/1)
    # We're going to skip doctype parsing for now
    |> Stream.filter(&elem(&1, 0) != "DOCTYPE")
    |> CharacterJoin.transform()
    |> Enum.to_list()
  end

  defp format_actual(input) do
    input
    |> HTMLParser.Tokenizer.tokenize()
    |> Stream.filter(fn
      ({:whitespace, _, _}) -> false
      # skip doctype/declaration parsing for now
      ({:declaration, _, _}) -> false
      (_) -> true
    end)
    |> HTMLParser.Transform.Entity.transform()
    |> HTMLParser.Transform.Attribute.transform(%{default_value: ""})
    |> HTMLParser.Transform.TagOpen.transform(%{attributes_into: %{}})
    |> HTMLParser.Transform.MergeText.transform()
    |> Stream.map(fn
      ({:text, _, text}) ->
        {"Character", text}
      ({:comment, _, data}) ->
        {"Comment", data}
      ({:tag_open, _, {name, attrs}}) ->
        {"StartTag", name, attrs}
      ({:tag_close, _, name}) ->
        {"EndTag", name}
      (other) ->
        other
    end)
    |> Enum.to_list()
  end
end
