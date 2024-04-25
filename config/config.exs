import Config

config :libring,
  rings: [
    # A ring which automatically changes based on Erlang cluster membership,
    # but does not allow nodes named "a" or "remsh*" to be added to the ring
    kv_ring: [monitor_nodes: true, node_type: :visible]
  ]
