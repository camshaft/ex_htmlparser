defprotocol HTMLParser.Tokenizer.Handler do
  defmodule ModuleState do
    defstruct [:handler, :state]
  end

  def init(handler)
  def text(handler, data)
  def open_tag_name(handler, data)
  def open_tag_end(handler)
  def close_tag(handler, data)
  def self_closing_tag(handler)
  def attribute_data(handler, data)
  def attribute_end(handler)
  def declaration(handler, data)
  def processing_instruction(handler, data)
  def comment(handler, data)
  def cdata(handler, data)
end

defimpl HTMLParser.Tokenizer.Handler, for: HTMLParser.Tokenizer.Handler.ModuleState do
  def init(%{handler: handler} = s) do
    %{s | state: handler.init()}
  end

  functions = HTMLParser.Tokenizer.Handler.__info__(:functions) -- [__protocol__: 1, impl_for: 1, impl_for!: 1, init: 1]

  for {fun, arity} <- functions do
    args = case arity - 1 do
      0 -> []
      a -> 1..a |> Enum.map(&Macro.var(:"arg#{&1}", nil))
    end
    def unquote(fun)(%{handler: handler} = s, unquote_splicing(args)) do
      %{s | state: handler.unquote(fun)(unquote_splicing(args))}
    end
  end
end
