defmodule Web do
  use Plug.Router
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  plug(:dispatch)

  def child_spec(_arg) do
    Plug.Cowboy.child_spec(
      scheme: :http,
      plug: __MODULE__,
      options: [
        port:
          get_free_port(
            8080 +
              String.to_integer(Enum.at(String.split(Atom.to_string(Node.self()), ["_", "@"]), 1))
          )
      ]
    )
  end

  defp get_free_port(start) do
    case :gen_tcp.listen(start, [:binary]) do
      {:ok, socket} ->
        :ok = :gen_tcp.close(socket)
        start

      {:error, :eaddrinuse} ->
        get_free_port(start + 1)
    end
  end

  match "/whoami" do
    send_resp(conn, 200, Atom.to_string(Node.self()))
  end

  match "/ping" do
    send_resp(conn, 200, "pong")
  end

  match "/status" do
    nodes =
      BasicRing.Kv_old.get_shard_names()
      |> Enum.flat_map(&BasicRing.Tracker.where_is(&1))
      |> Enum.map(fn {{name, replica}, pid} ->
        %{name: name, replica: replica, node: Atom.to_string(node(pid))}
      end)
      |> Enum.sort()

    #

    IO.puts("nodes: #{inspect(nodes)}")

    {status, body} = {200, Poison.encode!(%{status: "Ok.", nodes: nodes})}
    conn |> put_resp_content_type("text/json") |> send_resp(status, body)
  end

  match _ do
    send_resp(conn, 404, "oops... Nothing here :(")
  end
end
