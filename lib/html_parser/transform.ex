defmodule HTMLParser.Transform do
  defmacro __using__(opts) do
    entry = opts[:entry] || :transform
    quote do
      if !Module.defines?(__MODULE__, {unquote(entry), 1}, :def) do
        def unquote(entry)(stream, opts \\ %{})
      end
      def unquote(entry)(stream, opts) do
        Stream.resource(
          fn -> {stream, init(opts)} end,
          &__transform__/1,
          fn(_) -> nil end
        )
      end

      defp __transform__(nil) do
        {:halt, nil}
      end
      defp __transform__({stream, state}) do
        case Nile.Utils.next(stream) do
          {status, _stream} when status in [:done, :halted] ->
            {handle_eos(state), nil}
          {:suspended, token, stream} ->
            {acc, state} = handle_token(token, state)
            {acc, {stream, state}}
        end
      end

      def init(opts) do
        opts
      end

      def handle_token(token, state) do
        {[token], state}
      end

      def handle_eos(state) do
        []
      end

      defoverridable [init: 1, handle_token: 2, handle_eos: 1]
    end
  end
end
