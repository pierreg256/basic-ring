defmodule BasicRing.Kv do
  require Logger
  use BasicRing.Crdt

  def put(key, value) do
    Logger.debug("put: #{inspect(@crdt)}")
    DeltaCrdt.put(@crdt, key, value)
  end
end
