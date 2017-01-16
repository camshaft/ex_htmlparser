defmodule HTMLParser.Tokenizer.Macros do
  defmacro if_else_state(state, upper, success, failure) do
    quote bind_quoted: [
      state: state,
      upper: upper,
      success: success,
      failure: failure
    ] do
      lower = [upper] |> to_string() |> String.downcase
      chars = [upper, lower] |> Enum.uniq()

      defp tokenize(unquote(state), c, %{section: s} = state) when c in unquote(chars) do
        {unquote(success), %{state | section: [c | s]}}
      end
      defp tokenize(unquote(state), c, %{section: s} = state) do
        {unquote(failure), %{state | section: [c | s]}}
      end
    end
  end

  defmacro emit_whitespace(state) do
    quote do
      case unquote(state) do
        %{whitespace: []} = state ->
          state
        %{tokens: tokens, whitespace: ws} = state ->
          ws = ws |> :lists.reverse() |> :erlang.iolist_to_binary()
          %{state | tokens: [{:whitespace, nil, ws} | tokens], whitespace: []}
      end
    end
  end

  defmacro emit_token(state, type) do
    quote do
      t = unquote(type)
      case unquote(state) do
        %{tokens: tokens, whitespace: [], line: l} = state ->
          t = {t, l}
          %{state | tokens: [t | tokens]}
        %{tokens: tokens, whitespace: ws, line: l} = state ->
          t = {t, l}
          ws = ws |> :lists.reverse() |> :erlang.iolist_to_binary()
          %{state | tokens: [t, {:whitespace, nil, ws} | tokens], whitespace: []}
      end
    end
  end

  defmacro emit_token_ss(state, type) do
    quote do
      t = unquote(type)
      case unquote(state) do
        %{tokens: tokens, section: section, whitespace: [], line: l} = state ->
          section = section |> :lists.reverse() |> :erlang.iolist_to_binary()
          token = {t, l, section}
          %{state | tokens: [token | tokens], section: []}
        %{tokens: tokens, section: section, whitespace: ws, line: l} = state ->
          section = section |> :lists.reverse() |> :erlang.iolist_to_binary()
          ws = ws |> :lists.reverse() |> :erlang.iolist_to_binary()
          token = {t, l, section}
          %{state | tokens: [token, {:whitespace, nil, ws} | tokens], section: [], whitespace: []}
      end
    end
  end
end
