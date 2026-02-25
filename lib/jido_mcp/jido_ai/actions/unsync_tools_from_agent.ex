defmodule Jido.MCP.JidoAI.Actions.UnsyncToolsFromAgent do
  @moduledoc """
  Remove previously synced MCP proxy tools from a running `Jido.AI.Agent`.
  """

  use Jido.Action,
    name: "mcp_ai_unsync_tools",
    description: "Unsync MCP tools from a running Jido.AI agent",
    schema:
      Zoi.object(%{
        endpoint_id: Zoi.any(description: "Configured MCP endpoint id (atom or string)"),
        agent_server: Zoi.any(description: "PID or registered name of the running Jido.AI agent")
      })

  alias Jido.MCP.EndpointID
  alias Jido.MCP.JidoAI.ProxyRegistry

  @impl true
  def run(params, _context) do
    with :ok <- ensure_jido_ai_loaded(),
         {:ok, endpoint_id} <- EndpointID.resolve(params[:endpoint_id]) do
      jido_ai = Module.concat([Jido, AI])
      entries = ProxyRegistry.active(endpoint_id)

      {removed, failed} =
        Enum.reduce(entries, {[], []}, fn entry, {ok, err} ->
          case apply(jido_ai, :unregister_tool, [params[:agent_server], entry.local_name]) do
            {:ok, _agent} -> {[entry.local_name | ok], err}
            {:error, reason} -> {ok, [{entry.local_name, reason} | err]}
          end
        end)

      ProxyRegistry.clear_active(endpoint_id)

      {:ok,
       %{
         endpoint_id: endpoint_id,
         removed_count: length(removed),
         failed_count: length(failed),
         removed_tools: Enum.reverse(removed),
         failed: Enum.reverse(failed)
       }}
    end
  end

  defp ensure_jido_ai_loaded do
    module = Module.concat([Jido, AI])

    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, :jido_ai_not_available}
    end
  end
end
