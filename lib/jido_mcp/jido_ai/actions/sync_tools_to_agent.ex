defmodule Jido.MCP.JidoAI.Actions.SyncToolsToAgent do
  @moduledoc """
  Sync MCP tools from an endpoint into a running `Jido.AI.Agent` as proxy Jido actions.
  """

  use Jido.Action,
    name: "mcp_ai_sync_tools",
    description: "Sync MCP tools to a running Jido.AI agent",
    schema:
      Zoi.object(%{
        endpoint_id: Zoi.any(description: "Configured MCP endpoint id (atom or string)"),
        agent_server: Zoi.any(description: "PID or registered name of the running Jido.AI agent"),
        prefix:
          Zoi.string(description: "Optional local tool name prefix")
          |> Zoi.optional(),
        replace_existing:
          Zoi.boolean(
            description: "Unregister previously synced tools for this endpoint before syncing"
          )
          |> Zoi.default(true)
      })

  alias Jido.MCP.EndpointID
  alias Jido.MCP.JidoAI.{ProxyGenerator, ProxyRegistry}

  @default_max_tools_per_sync 100
  @default_max_proxy_modules_per_endpoint 200

  @impl true
  def run(params, _context) do
    with :ok <- ensure_jido_ai_loaded(),
         {:ok, endpoint_id} <- EndpointID.resolve(params[:endpoint_id]),
         {:ok, response} <- Jido.MCP.list_tools(endpoint_id),
         tools when is_list(tools) <- get_in(response, [:data, "tools"]) || [],
         :ok <- validate_tool_count(tools),
         {:ok, slot_map} <- assign_slots(endpoint_id, tools),
         {:ok, entries, warnings} <-
           ProxyGenerator.build_modules(endpoint_id, tools,
             prefix: params[:prefix],
             slot_map: slot_map
           ) do
      if params[:replace_existing] != false do
        _ = unregister_previous(params[:agent_server], endpoint_id)
      end

      {registered, failed} = register_modules(params[:agent_server], entries)
      ProxyRegistry.set_active(endpoint_id, registered)

      {:ok,
       %{
         endpoint_id: endpoint_id,
         discovered_count: length(tools),
         registered_count: length(registered),
         failed_count: length(failed),
         failed: failed,
         warnings: warnings,
         registered_tools: Enum.map(registered, & &1.local_name),
         max_tools_per_sync: max_tools_per_sync(),
         max_proxy_modules_per_endpoint: max_proxy_modules_per_endpoint()
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

  defp register_modules(agent_server, entries) do
    jido_ai = Module.concat([Jido, AI])

    Enum.reduce(entries, {[], []}, fn entry, {ok, err} ->
      case apply(jido_ai, :register_tool, [agent_server, entry.module]) do
        {:ok, _agent} -> {[entry | ok], err}
        {:error, reason} -> {ok, [{entry.local_name, reason} | err]}
      end
    end)
    |> then(fn {ok, err} -> {Enum.reverse(ok), Enum.reverse(err)} end)
  end

  defp unregister_previous(agent_server, endpoint_id) do
    jido_ai = Module.concat([Jido, AI])

    endpoint_id
    |> ProxyRegistry.active()
    |> Enum.each(fn entry ->
      _ = apply(jido_ai, :unregister_tool, [agent_server, entry.local_name])
    end)

    ProxyRegistry.clear_active(endpoint_id)
    :ok
  end

  defp validate_tool_count(tools) do
    count = length(tools)
    max = max_tools_per_sync()

    if count > max, do: {:error, {:too_many_tools, count, max}}, else: :ok
  end

  defp assign_slots(endpoint_id, tools) do
    remote_names =
      tools
      |> Enum.map(&Map.get(&1, "name"))
      |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))

    ProxyRegistry.assign_slots(endpoint_id, remote_names, max_proxy_modules_per_endpoint())
  end

  defp max_tools_per_sync do
    config_value(:max_tools_per_sync, @default_max_tools_per_sync)
  end

  defp max_proxy_modules_per_endpoint do
    config_value(:max_proxy_modules_per_endpoint, @default_max_proxy_modules_per_endpoint)
  end

  defp config_value(key, default) do
    sync_config = Application.get_env(:jido_mcp, :jido_ai_sync, [])

    value =
      case sync_config do
        %{} -> Map.get(sync_config, key, Map.get(sync_config, to_string(key), default))
        list when is_list(list) -> Keyword.get(list, key, default)
        _ -> default
      end

    if is_integer(value) and value > 0, do: value, else: default
  end
end
