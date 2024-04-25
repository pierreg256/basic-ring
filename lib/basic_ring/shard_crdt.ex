defmodule BasicRing.ShardCrdt do
  require Logger

  defmodule ShardCrdtSupervisor do
    alias BasicRing.ShardCrdt
    use Supervisor

    def start_link(init_opts) do
      #      Supervisor.start_link(__MODULE__, init_opts, name: :"#{__MODULE__}.#{init_opts[:shard]}")
      Supervisor.start_link(__MODULE__, init_opts,
        name: Module.concat(__MODULE__, Integer.to_string(init_opts[:shard]))
      )
    end

    @impl true
    def init(init_opts) do
      Logger.warning("init ops:#{__MODULE__} - #{inspect(init_opts)}")

      crdt_opts =
        [crdt: DeltaCrdt.AWLWWMap]
        |> Keyword.merge(init_opts)
        |> Keyword.put(
          :name,
          Module.concat("Crdt", Integer.to_string(init_opts[:shard]))
        )

      cluster_opts =
        [
          crdt: crdt_opts[:name],
          name: Module.concat(ShardCrdt, Integer.to_string(init_opts[:shard]))
        ]
        |> Keyword.merge(init_opts)

      Logger.error("cluster_opts: #{inspect(cluster_opts)}")

      children = [
        DeltaCrdt.child_spec(crdt_opts) |> Map.put(:id, crdt_opts[:name]),
        %{
          id: cluster_opts[:name],
          start: {BasicRing.ShardCrdt, :start_link, [cluster_opts]}
        },
        BasicRing.NodeListener.child_spec(
          Module.concat(ShardCrdt, Integer.to_string(init_opts[:shard]))
        )
      ]

      Logger.debug("children: #{inspect(children)}")
      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  use GenServer

  def child_spec(opts) do
    spec = ShardCrdtSupervisor.child_spec(opts)
    %{spec | id: Module.concat(ShardCrdtSupervisor, Integer.to_string(opts[:shard]))}
  end

  def start_link(opts) do
    Logger.warning("start_link: #{inspect(opts)}")

    GenServer.start_link(
      __MODULE__,
      opts,
      name: opts[:name]
    )
  end

  @impl true
  def init(opts) do
    Logger.warning("init ops:#{__MODULE__} - #{inspect(opts)}")
    members = BasicRing.NodeListener.make_members(opts[:name])

    state =
      opts
      |> Enum.into(%{})
      |> Map.put(:members, members)

    Logger.debug("name: #{inspect(opts[:name])}, init with state: #{inspect(state)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:set_members, members}, _from, state = %{crdt: crdt, name: name}) do
    Logger.warning("name: #{inspect(name)}, setting members: #{inspect(members)}")

    neighbors =
      members
      |> Stream.filter(fn member -> member != {name, Node.self()} end)
      |> Enum.map(fn {_, node} -> {crdt, node} end)

    DeltaCrdt.set_neighbours(crdt, neighbors)

    {:reply, :ok, %{state | members: members}}
  end

  @impl true
  def handle_call(:members, _from, state = %{members: members}) do
    {:reply, MapSet.to_list(members), state}
  end
end
