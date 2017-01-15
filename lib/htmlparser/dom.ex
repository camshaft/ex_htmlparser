defmodule HTMLParser.DOM do
  defmodule Comment do
    defstruct [:data, :info]
  end
  defmodule Directive do
    defstruct [:name, :data, :info]

    defimpl String.Chars do
      def to_string(%{data: data}) do
        "<" <> data <> ">"
      end
    end
  end
  defmodule Element do
    defstruct [name: nil,
               attributes: nil,
               children: [],
               info: nil,
               self_closing: false]

    defimpl String.Chars do
      def to_string(%{name: name, children: children}) do
        [
          "<", name, ">",
          Enum.join(children, ""),
          "</", name, ">"
        ]
        |> :erlang.iolist_to_binary()
      end
    end
  end
  defmodule Script do
    defstruct [attributes: nil, children: [], info: nil]
  end
  defmodule Style do
    defstruct [attributes: nil, children: [], info: nil]
  end
  defmodule Text do
    defstruct [:data, :info]

    defimpl String.Chars do
      def to_string(%{data: data}) do
        data
      end
    end
  end

  defstruct [dom: [], normalize_whitespace: false]

  def collect(stream, opts \\ %{}) do
    Enum.into(stream, %__MODULE__{normalize_whitespace: !!opts[:normalize_whitespace]})
  end

  defimpl String.Chars do
    def to_string(%{dom: dom}) do
      Enum.join(dom, "")
    end
  end
end

defimpl Enumerable, for: HTMLParser.DOM do
  def count(_) do
    {:error, __MODULE__}
  end

  def member?(_, _) do
    {:error, __MODULE__}
  end

  def reduce(%{dom: dom}, acc, fun) do
    @protocol.reduce(dom, acc, fun)
  end
end

defimpl Collectable, for: HTMLParser.DOM do
  alias HTMLParser.DOM.{Comment,Directive,Element,Script,Style,Text}

  def into(%{dom: dom, normalize_whitespace: normalize}) do
    state = %{
      dom: dom,
      normalize: normalize,
      stack: [],
      whitespace: []
    }
    {state, &collect/2}
  end

  defp collect(_state, :halt) do
    :ok
  end
  defp collect(%{dom: dom, normalize: normalize}, :done) do
    %@for{
      dom: :lists.reverse(dom),
      normalize_whitespace: normalize
    }
  end
  defp collect(state, {:cont, token}) do
    handle_token(state, token)
  end

  defp handle_token(state, {:close_tag, _name}) do
    pop(state)
  end

  defp handle_token(state, {:open_tag, info, "script", attrs}) do
    el = %Script{attributes: attrs, info: info}
    push(state, el)
  end
  defp handle_token(state, {:open_tag, info, "style", attrs}) do
    el = %Style{attributes: attrs, info: info}
    push(state, el)
  end
  defp handle_token(state, {:open_tag, info, name, attrs}) do
    el = %Element{name: name, attributes: attrs, info: info}
    push(state, el)
  end
  # TODO merge text nodes
  # defp handle_token(%{stack: [], dom: [%Text{} | _]} = state, {:text, data}) do
    # data = normalize(state, data)
    # state
  # end
  defp handle_token(state, {:text, info, data}) do
    el = %Text{data: normalize(state, data), info: info}
    state
    |> push(el)
    |> pop()
  end

  defp handle_token(state, {:comment, info, data}) do
    # TODO acc comment data
    el = %Comment{data: data, info: info}
    state
    |> push(el)
  end
  defp handle_token(state, :comment_end) do
    pop(state)
  end

  defp handle_token(state, {:instruction, info, name, data}) do
    el = %Directive{name: name, data: data, info: info}
    state
    |> push(el)
    |> pop()
  end

  defp handle_token(%{whitespace: w} = state, {:whitespace, _, ws}) do
    %{state | whitespace: [ws | w]}
  end

  # skip
  defp handle_token(state, {name, _, _})
  when name in [:open_tag_name] do
    state
  end
  defp handle_token(state, {name, _, _, _})
  when name in [:attribute] do
    state
  end

  defp normalize(%{normalize: true}, text) do
    Regex.replace(~r/\s+/, text, " ")
  end
  defp normalize(_, text) do
    text
  end

  defp push(%{stack: stack} = state, el) do
    %{state | stack: [el | stack]}
  end

  defp pop(%{stack: [%{children: el_c} = el, %{children: parent_c} = parent | stack]} = state) do
    %{state | stack: [%{parent | children: [%{el | children: :lists.reverse(el_c)} | parent_c]} | stack]}
  end
  defp pop(%{stack: [el, %{children: parent_c} = parent | stack]} = state) do
    %{state | stack: [%{parent | children: [el | parent_c]} | stack]}
  end
  defp pop(%{stack: [el], dom: dom} = state) do
    %{state | stack: [], dom: [el | dom]}
  end
end
