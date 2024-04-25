defmodule BasicRing do
  @moduledoc """
  Documentation for `BasicRing`.
  """

  def test do
    Benchee.run(%{
      :put => fn ->
        BasicRing.Kv_old.put(
          :crypto.strong_rand_bytes(10) |> Base.encode64(),
          :crypto.strong_rand_bytes(10) |> Base.encode64()
        )
      end,
      :get => fn ->
        BasicRing.Kv_old.get(:crypto.strong_rand_bytes(10) |> Base.encode64())
      end
    })

    # base |> Enum.map(fn {key, value} -> BasicRing.Kv.put(key, value) end)
    # # Process.sleep(1000)

    # base |> Enum.map(fn {key, value} -> BasicRing.Kv.get(key) end) |> Enum.sort() |> IO.inspect()

    # key = :crypto.strong_rand_bytes(10) |> Base.encode64()
    # value = :crypto.strong_rand_bytes(10) |> Base.encode64()
    # IO.puts(" #{inspect(BasicRing.Kv.put(key, value))}")
    # Process.sleep(10)

    # nodes =
    #   Enum.map(1..100, fn _ ->
    #     {:ok, replica, _value} = BasicRing.Kv.get(key)
    #     replica
    #   end)

    # Enum.reduce(nodes, %{}, fn node, acc ->
    #   Map.update(acc, node, 1, &(&1 + 1))
    # end)

    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    # IO.puts("#{value} == #{inspect(BasicRing.Kv.get(key))}")
    :ok
  end
end
