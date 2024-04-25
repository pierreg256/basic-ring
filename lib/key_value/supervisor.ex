defmodule KeyValue.Supervisor do
  use Supervisor

  def start_link(_arg) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      DeltaCrdt.child_spec(
        crdt: DeltaCrdt.AWLWWMap,
        name: via_tuple(Node.self(), 0),
        sync_interval: 10
      )
    ]

    BasicRing.Kv_old.get_shard_names()
    |> Enum.map(fn shard -> {shard, HashRing.Managed.key_to_node(:kv_ring, shard)} end)
    |> Enum.filter(fn {_shard, node} -> node == Node.self() end)
    |> inspect()
    |> IO.puts()

    # |> Enum.map(fn shard -> DeltaCrdt.child_spec(crdt: DeltaCrdt.AWLWWMap, name: via_tuple(shard, 0), sync_interval: 10) end)
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp via_tuple(name, replica) do
    {:via, Horde.Registry, {BasicRing.RingRegistry, {name, replica}, name}}
  end
end
