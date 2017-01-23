defmodule Test.HTMLParser.Case do
  use ExUnit.CaseTemplate, async: true

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  defmacro bench(name, count, [do: body]) do
    quote do
      @tag :bench
      test "benchmark #{unquote(name)}" do
        {a, b} = unquote(body)
        count = unquote(count)
        a = unquote(__MODULE__).__bench__("control", a, count)
        b = unquote(__MODULE__).__bench__("subject", b, count)
        try do
          IO.puts "\n"
          IO.puts unquote(name)
          :eministat.x(95.0, a, b)
        rescue
          _ ->
            IO.puts "no difference"
        end
      end
    end
  end

  def __bench__(name, fun, count) do
    warm(fun, 0)
    :eministat_ds.from_list(name, measure(fun, count, []))
  end

  defp warm(_, time) when time >= 2_000_000 do
    :ok
  end
  defp warm(fun, time) do
    case :timer.tc(fun) do
      {0, _} ->
        warm(fun, time + 1)
      {t, _} ->
        warm(fun, time + t)
    end
  end

  defp measure(_, 0, acc) do
    :lists.reverse(acc)
  end
  defp measure(fun, count, acc) do
    :erlang.garbage_collect()
    {t, _} = :timer.tc(fun)
    measure(fun, count - 1, [t | acc])
  end
end

ExUnit.start()
