defmodule BasicRing.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = [
      basic_ring: [
        strategy: Cluster.Strategy.Gossip
      ]
    ]

    children = [
      # Starts a worker by calling: BasicRing.Worker.start_link(arg)
      # {BasicRing.Worker, arg}
      {Cluster.Supervisor, [topologies, [name: BasicRing.ClusterSupervisor]]},
      {Horde.Registry,
       [
         name: BasicRing.RingRegistry,
         keys: :unique,
         members: :auto,
         delta_crdt_options: [sync_interval: 10]
       ]},
      {DynamicSupervisor, name: BasicRing.KvSupervisor, strategy: :one_for_one},
      {BasicRing.Tracker, name: BasicRing.Tracker, strategy: :one_for_one},
      # {KeyValue.Supervisor, name: KeyValue.Supervisor, strategy: :one_for_one},
      {Web, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BasicRing.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
