defmodule Jido.MCP.AnubisClient do
  @moduledoc false

  @client_info %{
    "name" => "JidoMCP",
    "version" => to_string(Application.spec(:jido_mcp, :vsn) || "0.1.1")
  }

  @spec client_info() :: map()
  def client_info, do: @client_info

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    opts
    |> Keyword.put_new(:client_info, @client_info)
    |> Anubis.Client.start_link()
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end
end
