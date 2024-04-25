defmodule KeyValue.Worker do
  use GenServer

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {:ok, %{data: %{}, sync_interval: 10}}
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state.data, key), state}
  end

  def handle_call({:put, key, value}, _from, state) do
    new_data = Map.put(state.data, key, value)
    {:reply, :ok, %{state | data: new_data}}
  end

  def handle_info(:sync, state) do
    IO.puts("Syncing data to disk")
    {:noreply, state}
  end
end
