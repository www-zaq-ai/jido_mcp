unless Code.ensure_loaded?(Jido.AI) do
  defmodule :"Elixir.Jido.AI" do
    def register_tool(agent_server, module) do
      Agent.update(agent_server, &Map.put(&1, module.name(), module))
      {:ok, agent_server}
    end

    def unregister_tool(agent_server, name) do
      Agent.update(agent_server, &Map.delete(&1, name))
      {:ok, agent_server}
    end
  end
end

defmodule Jido.MCP.JidoAI.SyncActionsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.MCP.JidoAI.Actions.{SyncToolsToAgent, UnsyncToolsFromAgent}
  alias Jido.MCP.JidoAI.ProxyRegistry

  setup :set_mimic_private
  setup :verify_on_exit!

  setup do
    original_endpoints = Application.get_env(:jido_mcp, :endpoints)
    original_sync = Application.get_env(:jido_mcp, :jido_ai_sync)

    Application.put_env(:jido_mcp, :endpoints, %{
      sync: %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "test"}
      },
      over_limit: %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "test"}
      },
      budget: %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "test"}
      }
    })

    Application.put_env(:jido_mcp, :jido_ai_sync,
      max_tools_per_sync: 100,
      max_proxy_modules_per_endpoint: 200
    )

    ProxyRegistry.reset()

    on_exit(fn ->
      ProxyRegistry.reset()

      if is_nil(original_endpoints) do
        Application.delete_env(:jido_mcp, :endpoints)
      else
        Application.put_env(:jido_mcp, :endpoints, original_endpoints)
      end

      if is_nil(original_sync) do
        Application.delete_env(:jido_mcp, :jido_ai_sync)
      else
        Application.put_env(:jido_mcp, :jido_ai_sync, original_sync)
      end
    end)

    :ok
  end

  defp start_agent(initial_state) do
    start_supervised!(%{id: make_ref(), start: {Agent, :start_link, [fn -> initial_state end]}})
  end

  test "syncs and unsyncs tools while preserving slot reuse" do
    tools = [
      %{
        "name" => "search",
        "description" => "Search",
        "inputSchema" => %{"type" => "object", "properties" => %{"q" => %{"type" => "string"}}}
      },
      %{
        "name" => "list",
        "description" => "List",
        "inputSchema" => %{"type" => "object", "properties" => %{}}
      }
    ]

    expect(Jido.MCP, :list_tools, 2, fn :sync ->
      {:ok, %{data: %{"tools" => tools}}}
    end)

    agent_server = start_agent(%{})

    assert {:ok, first_result} =
             SyncToolsToAgent.run(
               %{
                 endpoint_id: "sync",
                 agent_server: agent_server,
                 prefix: "proxy_",
                 replace_existing: true
               },
               %{}
             )

    assert first_result.discovered_count == 2
    assert first_result.registered_count == 2

    first_active = ProxyRegistry.active(:sync)
    first_modules = Enum.map(first_active, & &1.module)

    assert {:ok, %{removed_count: 2}} =
             UnsyncToolsFromAgent.run(%{endpoint_id: :sync, agent_server: agent_server}, %{})

    assert [] == ProxyRegistry.active(:sync)

    assert {:ok, second_result} =
             SyncToolsToAgent.run(
               %{
                 endpoint_id: :sync,
                 agent_server: agent_server,
                 prefix: "proxy_",
                 replace_existing: true
               },
               %{}
             )

    assert second_result.registered_count == 2

    second_active = ProxyRegistry.active(:sync)
    second_modules = Enum.map(second_active, & &1.module)

    assert first_modules == second_modules
  end

  test "refuses sync when discovered tools exceed max_tools_per_sync" do
    Application.put_env(:jido_mcp, :jido_ai_sync,
      max_tools_per_sync: 1,
      max_proxy_modules_per_endpoint: 10
    )

    expect(Jido.MCP, :list_tools, fn :over_limit ->
      {:ok,
       %{
         data: %{
           "tools" => [
             %{"name" => "a", "inputSchema" => %{"type" => "object", "properties" => %{}}},
             %{"name" => "b", "inputSchema" => %{"type" => "object", "properties" => %{}}}
           ]
         }
       }}
    end)

    agent_server = start_agent(%{})

    assert {:error, {:too_many_tools, 2, 1}} =
             SyncToolsToAgent.run(%{endpoint_id: :over_limit, agent_server: agent_server}, %{})
  end

  test "refuses sync when proxy module budget is exceeded" do
    Application.put_env(:jido_mcp, :jido_ai_sync,
      max_tools_per_sync: 10,
      max_proxy_modules_per_endpoint: 1
    )

    counter = start_agent(0)

    expect(Jido.MCP, :list_tools, 2, fn :budget ->
      idx = Agent.get_and_update(counter, fn value -> {value, value + 1} end)

      tools =
        if idx == 0 do
          [%{"name" => "alpha", "inputSchema" => %{"type" => "object", "properties" => %{}}}]
        else
          [%{"name" => "beta", "inputSchema" => %{"type" => "object", "properties" => %{}}}]
        end

      {:ok, %{data: %{"tools" => tools}}}
    end)

    agent_server = start_agent(%{})

    assert {:ok, %{registered_count: 1}} =
             SyncToolsToAgent.run(%{endpoint_id: :budget, agent_server: agent_server}, %{})

    assert {:error, {:proxy_module_budget_exceeded, :budget, 1}} =
             SyncToolsToAgent.run(%{endpoint_id: :budget, agent_server: agent_server}, %{})
  end

  test "rejects unknown endpoint ids before fetching tools" do
    reject(Jido.MCP, :list_tools, 1)

    agent_server = start_agent(%{})

    assert {:error, :unknown_endpoint} =
             SyncToolsToAgent.run(%{endpoint_id: "missing", agent_server: agent_server}, %{})
  end
end
