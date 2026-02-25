defmodule Jido.MCP.Actions.HelpersTest do
  use ExUnit.Case, async: false

  alias Jido.MCP.Actions.Helpers

  setup do
    original = Application.get_env(:jido_mcp, :endpoints)

    Application.put_env(:jido_mcp, :endpoints, %{
      github: %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "test"}
      },
      filesystem: %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "test"}
      }
    })

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_mcp, :endpoints)
      else
        Application.put_env(:jido_mcp, :endpoints, original)
      end
    end)

    :ok
  end

  test "resolves endpoint id from params" do
    assert {:ok, :github} = Helpers.resolve_endpoint_id(%{endpoint_id: :github}, %{})
    assert {:ok, :github} = Helpers.resolve_endpoint_id(%{endpoint_id: "github"}, %{})
  end

  test "enforces allowed_endpoints" do
    context = %{allowed_endpoints: [:github]}

    assert {:ok, :github} = Helpers.resolve_endpoint_id(%{endpoint_id: :github}, context)

    assert {:error, :endpoint_not_allowed} =
             Helpers.resolve_endpoint_id(%{endpoint_id: :filesystem}, context)
  end

  test "rejects invalid allowed_endpoints values" do
    assert {:error, :invalid_allowed_endpoints} =
             Helpers.resolve_endpoint_id(%{endpoint_id: :github}, %{
               allowed_endpoints: ["missing"]
             })

    assert {:error, :invalid_allowed_endpoints} =
             Helpers.resolve_endpoint_id(%{endpoint_id: :github}, %{allowed_endpoints: :github})
  end
end
