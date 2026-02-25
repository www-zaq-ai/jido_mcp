defmodule Jido.MCP.JidoAI.ProxyRegistryTest do
  use ExUnit.Case, async: false

  alias Jido.MCP.JidoAI.ProxyRegistry

  setup do
    ProxyRegistry.reset()

    on_exit(fn ->
      ProxyRegistry.reset()
    end)

    :ok
  end

  test "assigns stable slots and reuses existing assignments" do
    assert {:ok, slots} = ProxyRegistry.assign_slots(:github, ["alpha", "beta"], 3)
    assert slots == %{"alpha" => 1, "beta" => 2}

    assert {:ok, slots} = ProxyRegistry.assign_slots(:github, ["beta", "gamma"], 3)
    assert slots == %{"beta" => 2, "gamma" => 3}

    assert ProxyRegistry.assignments(:github) == %{"alpha" => 1, "beta" => 2, "gamma" => 3}
  end

  test "returns budget exceeded when no slots are available" do
    assert {:ok, _} = ProxyRegistry.assign_slots(:github, ["alpha"], 1)

    assert {:error, {:proxy_module_budget_exceeded, :github, 1}} =
             ProxyRegistry.assign_slots(:github, ["beta"], 1)
  end

  test "stores and clears active registrations" do
    entry = %{module: String, local_name: "tool_1", remote_name: "alpha", slot: 1}

    assert :ok = ProxyRegistry.set_active(:github, [entry])
    assert [^entry] = ProxyRegistry.active(:github)

    assert :ok = ProxyRegistry.clear_active(:github)
    assert [] == ProxyRegistry.active(:github)
  end

  test "backward compatible wrappers store modules" do
    assert :ok = ProxyRegistry.put(:github, [Jido.MCP.Actions.ListTools])
    assert [Jido.MCP.Actions.ListTools] == ProxyRegistry.get(:github)

    assert :ok = ProxyRegistry.delete(:github)
    assert [] == ProxyRegistry.get(:github)
  end
end
