defmodule Jido.MCP.AnubisClientTest do
  use ExUnit.Case, async: true

  test "exposes client functions and child spec" do
    assert Code.ensure_loaded?(Jido.MCP.AnubisClient)
    assert function_exported?(Jido.MCP.AnubisClient, :child_spec, 1)
    assert function_exported?(Jido.MCP.AnubisClient, :start_link, 1)

    spec =
      Jido.MCP.AnubisClient.child_spec(
        name: :demo_client,
        transport: {:stdio, [command: "cat", args: []]}
      )

    assert is_map(spec)
    assert spec.id
  end
end
