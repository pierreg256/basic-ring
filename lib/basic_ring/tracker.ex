defmodule BasicRing.Tracker do
  alias Cluster.Strategy.TrackerState
  use GenServer

  require Logger

  @default_nb_replicas 3
  @default_nb_shards 16

  defmodule TrackerState do
    @type t :: %__MODULE__{
            ring: HashRing.t(),
            topology: [{non_neg_integer(), [atom()]}],
            nb_replicas: non_neg_integer(),
            nb_shards: non_neg_integer(),
            nodes: [atom()]
          }
    defstruct ring: nil, topology: [], nb_replicas: 0, nb_shards: 0, nodes: []
  end

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  defp create_topology([], _nodes, _nb_replicas), do: []

  defp create_topology([shard | shards], [node | nodes], nb_replicas) do
    case Enum.count([node | nodes]) do
      count when count < nb_replicas ->
        Logger.warning(
          "[basic_ring:tracker] Not enough nodes to create replicas for shard #{shard}."
        )

        []

      _ ->
        [
          {shard, [node | nodes] |> Enum.slice(0, nb_replicas)}
          | create_topology(shards, nodes ++ [node], nb_replicas)
        ]
    end
  end

  def init(init_arg) do
    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)

    nb_replicas = Keyword.get(init_arg, :nb_replicas, @default_nb_replicas)
    nb_shards = Keyword.get(init_arg, :nb_shards, @default_nb_shards)
    nodes = Node.list([:visible, :this]) |> Enum.uniq() |> Enum.sort()
    topology = create_topology(get_shards(nb_shards), nodes, nb_replicas)
    child = BasicRing.ShardCrdt.child_spec(shard: 1)
    Logger.debug("child1: #{inspect(child)}")
    res = DynamicSupervisor.start_child(BasicRing.KvSupervisor, child)
    Logger.debug("child1: #{inspect(res)}")
    # child = BasicRing.ShardCrdt.child_spec(shard: 2)
    # Logger.debug("child2: #{inspect(child)}")
    # res = DynamicSupervisor.start_child(BasicRing.KvSupervisor, child)
    # Logger.debug("child2: #{inspect(res)}")

    {:ok,
     %TrackerState{
       nb_replicas: nb_replicas,
       nb_shards: nb_shards,
       topology: topology,
       nodes: nodes,
       ring:
         HashRing.new()
         |> HashRing.add_nodes(Node.list([:visible, :this]))
     }}
  end

  def where_is(name) do
    GenServer.call(__MODULE__, {:where_is, name})
  end

  def start_worker(name) do
    GenServer.call(__MODULE__, {:start, name})
  end

  def start_replica_on_node(name, replica, node) do
    cond do
      Node.self() == node ->
        child =
          DeltaCrdt.child_spec(
            crdt: DeltaCrdt.AWLWWMap,
            name: via_tuple(name, replica),
            sync_interval: 10
          )

        DynamicSupervisor.start_child(BasicRing.KvSupervisor, child)

      true ->
        :rpc.call(node, BasicRing.Tracker, :start_replica_on_node, [name, replica, node])
    end
  end

  defp via_tuple(name, replica) do
    {:via, Horde.Registry, {BasicRing.RingRegistry, {name, replica}, name}}
  end

  def handle_call({:where_is, name}, _from, %TrackerState{} = state) do
    shard = shard_from_name(name, state)

    ret =
      Horde.Registry.select(BasicRing.RingRegistry, [
        {{:"$1", :"$2", :"$3"}, [{:==, :"$3", shard}], [{{:"$1", :"$2", :"$3"}}]}
      ])
      |> Enum.map(fn {name, pid, _} -> {name, pid} end)

    {:reply, ret, state}
  end

  def handle_call(
        {:start, name},
        _from,
        %TrackerState{ring: ring, nb_replicas: nb_replicas} = state
      ) do
    case HashRing.key_to_nodes(ring, name, nb_replicas) do
      nodes when is_list(nodes) ->
        cond do
          Enum.count(nodes) < nb_replicas ->
            {:reply, {:error, :not_enough_nodes, Enum.count(nodes), nb_replicas}, state}

          true ->
            ret =
              Enum.with_index(nodes, fn node, index ->
                case start_replica_on_node(name, index + 1, node) do
                  {:ok, pid} -> {{name, index + 1}, pid}
                  {:error, {:already_started, pid}} -> {{name, index + 1}, pid}
                  {:error, reason} -> {{name, index + 1}, reason}
                end
              end)

            Enum.map(ret, fn {_, pid} ->
              DeltaCrdt.set_neighbours(pid, ret |> Enum.map(fn {_, pid} -> pid end))
            end)

            {:reply, {:ok, ret}, state}
        end
    end
  end

  def handle_info({:nodeup, node, _opts}, %TrackerState{} = state) do
    Logger.info("[basic_ring:tracker] Node up: #{node}")

    new_ring =
      HashRing.new()
      |> HashRing.add_nodes(Node.list([:visible, :this]))

    new_nodes = Node.list([:visible, :this]) |> Enum.uniq() |> Enum.sort()

    new_topology =
      create_topology(get_shards(state.nb_shards), new_nodes, state.nb_replicas)

    new_state = %TrackerState{state | ring: new_ring, topology: new_topology, nodes: new_nodes}

    if has_quorum?(new_state) do
      start_shard(new_state)
    else
      Logger.warning("[basic_ring:tracker] Not enough nodes to start shards.")
    end

    {:noreply, new_state}
  end

  def handle_info({:nodedown, node, _opts}, %TrackerState{} = state) do
    Logger.warning("[basic_ring:tracker] Node down: #{node}")

    new_ring =
      HashRing.new()
      |> HashRing.add_nodes(Node.list([:visible, :this]))

    new_nodes = Node.list([:visible, :this]) |> Enum.uniq() |> Enum.sort()

    new_topology =
      create_topology(get_shards(state.nb_shards), new_nodes, state.nb_replicas)

    if Enum.count(new_topology) == 0 do
      Logger.error("[basic_ring:tracker] Not enough nodes available to create topology.")
    end

    {:noreply, %TrackerState{state | ring: new_ring, topology: new_topology, nodes: new_nodes}}
  end

  def handle_info(message, state) do
    IO.puts("Unhandled info message: #{inspect(message)}")
    {:noreply, state}
  end

  defp get_shards(nb_shards) do
    1..nb_shards |> Enum.map(& &1)
  end

  defp shard_from_name(name, %TrackerState{nb_shards: nb_shards} = _state) do
    :erlang.phash2(name, nb_shards)
  end

  defp has_quorum?(%TrackerState{} = state) do
    Enum.count(state.nodes) >= state.nb_replicas
  end

  defp start_shard(%TrackerState{topology: topology} = _state) do
    current_node = Node.self()

    topology
    |> Enum.filter(fn {_, nodes} -> Enum.member?(nodes, current_node) end)
    |> Enum.map(fn {name, nodes} ->
      {name, Enum.find_index(nodes, &(&1 == current_node)) + 1}
    end)
    |> inspect()
    |> IO.puts()
  end
end
