defmodule BasicRing.Kv_old do
  @nb_shards 16
  @nb_replicas 3

  alias BasicRing.Tracker

  def get(key) do
    shard = shard_from_key(key)

    {{shard, replica}, pid} =
      case Tracker.where_is(shard) do
        [] ->
          {:ok, pids} = Tracker.start_worker(shard)
          Enum.random(pids)

        pids when is_list(pids) ->
          Enum.random(pids)
      end

    value = DeltaCrdt.get(pid, key)
    {:ok, {shard, replica}, value}
  end

  def put(key, value) do
    shard = shard_from_key(key)

    {{shard, replica}, pid} =
      case Tracker.where_is(shard) do
        [] ->
          {:ok, pids} = Tracker.start_worker(shard)
          Enum.random(pids)

        pids when is_list(pids) ->
          Enum.random(pids)
      end

    DeltaCrdt.put(pid, key, value)
    {:ok, {shard, replica}, value}
  end

  def get_shard_names() do
    Enum.map(1..@nb_shards, & &1)
  end

  def select_replica(key) do
    shard = shard_from_key(key)

    case Horde.Registry.select(BasicRing.RingRegistry, [
           {{:"$1", :"$2", :"$3"}, [{:==, :"$3", shard}], [{{:"$1", :"$2", :"$3"}}]}
         ]) do
      [] ->
        get_replicas(key) |> Enum.random()

      result ->
        {_, pid, _} = result |> Enum.sort() |> Enum.random()
        pid
    end
  end

  defp get_replicas(key) do
    siblings =
      HashRing.new()
      |> HashRing.add_nodes(HashRing.Managed.nodes(:kv_ring))
      |> HashRing.key_to_nodes(shard_from_key(key), @nb_replicas)
      |> Enum.reduce([], fn node, acc ->
        replica = Enum.count(acc) + 1

        child =
          DeltaCrdt.child_spec(
            crdt: DeltaCrdt.AWLWWMap,
            name: via_tuple(shard_from_key(key), replica),
            sync_interval: 10
          )

        pid =
          case :rpc.call(node, DynamicSupervisor, :start_child, [BasicRing.KvSupervisor, child]) do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
            {:error, reason} -> {:error, reason}
          end

        [pid | acc]
      end)

    siblings |> Enum.map(fn pid -> DeltaCrdt.set_neighbours(pid, siblings) end)

    siblings
  end

  defp shard_from_key(key) do
    :erlang.phash2(key, @nb_shards)
  end

  defp via_tuple(shard, replica) when is_integer(shard) and is_integer(replica) do
    name = name(shard, replica)
    {:via, Horde.Registry, {BasicRing.RingRegistry, name, shard}}
  end

  defp name(shard, replica) when is_integer(shard) and is_integer(replica) do
    "kv_#{shard}_#{replica}"
  end
end
