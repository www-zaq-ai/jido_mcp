defmodule Jido.MCP.JidoAI.ProxyGeneratorTest do
  use ExUnit.Case, async: false

  alias Jido.MCP.JidoAI.ProxyGenerator

  test "builds proxy modules from bounded slots" do
    tools = [
      %{
        "name" => "search",
        "description" => "Search tool",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"q" => %{"type" => "string"}},
          "required" => ["q"]
        }
      }
    ]

    assert {:ok, [entry], warnings} =
             ProxyGenerator.build_modules(:proxy_a, tools,
               prefix: "tool_",
               slot_map: %{"search" => 1}
             )

    assert entry.slot == 1
    assert entry.local_name == "tool_search__1"
    assert entry.remote_name == "search"
    assert entry.module.__mcp_proxy__().remote_tool_name == "search"
    assert warnings == %{}
  end

  test "reuses the same module for the same slot assignment" do
    tools = [%{"name" => "search", "inputSchema" => %{"type" => "object", "properties" => %{}}}]

    assert {:ok, [first], _warnings} =
             ProxyGenerator.build_modules(:proxy_b, tools,
               prefix: "tool_",
               slot_map: %{"search" => 1}
             )

    assert {:ok, [second], _warnings} =
             ProxyGenerator.build_modules(:proxy_b, tools,
               prefix: "tool_",
               slot_map: %{"search" => 1}
             )

    assert first.module == second.module
    assert first.local_name == second.local_name
  end

  test "returns conflict when a slot is reassigned to a new remote name" do
    first_tools = [
      %{"name" => "alpha", "inputSchema" => %{"type" => "object", "properties" => %{}}}
    ]

    assert {:ok, [_entry], _warnings} =
             ProxyGenerator.build_modules(:proxy_c, first_tools,
               prefix: "tool_",
               slot_map: %{"alpha" => 1}
             )

    conflict_tools = [
      %{"name" => "beta", "inputSchema" => %{"type" => "object", "properties" => %{}}}
    ]

    assert {:error, {:proxy_module_slot_conflict, _module, "beta", "alpha"}} =
             ProxyGenerator.build_modules(:proxy_c, conflict_tools,
               prefix: "tool_",
               slot_map: %{"beta" => 1}
             )
  end
end
