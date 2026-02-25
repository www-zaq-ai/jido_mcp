defmodule Jido.MCP.ClientPoolTest do
  use ExUnit.Case, async: false

  alias Jido.MCP.{ClientPool, Config}

  setup do
    {:ok, _} = Application.ensure_all_started(:jido_mcp)
    old_state = :sys.get_state(ClientPool)

    endpoints =
      Config.normalize_endpoints(%{
        demo: %{
          transport: {:stdio, [command: "cat", args: []]},
          client_info: %{name: "test"}
        }
      })

    :sys.replace_state(ClientPool, fn state -> %{state | endpoints: endpoints, refs: %{}} end)

    on_exit(fn ->
      :sys.replace_state(ClientPool, fn _ -> old_state end)
    end)

    :ok
  end

  test "manages endpoint lifecycle and reports status" do
    assert {:error, :not_started} = ClientPool.endpoint_status(:demo)
    assert {:error, :unknown_endpoint} = ClientPool.ensure_client(:missing)

    assert {:ok, _endpoint, _ref} = ClientPool.ensure_client(:demo)

    assert {:ok, status} = ClientPool.endpoint_status(:demo)
    assert status.endpoint_id == :demo
    assert status.client_alive?
    assert status.supervisor_alive?
    assert status.transport_alive?

    assert {:ok, _endpoint, _ref} = ClientPool.refresh(:demo)
  end

  test "reports dead processes for stale refs" do
    :sys.replace_state(ClientPool, fn state ->
      %{
        state
        | refs: %{
            demo: %{
              client: :missing_client,
              supervisor: :missing_supervisor,
              transport: :missing_transport
            }
          }
      }
    end)

    assert {:ok, status} = ClientPool.endpoint_status(:demo)
    refute status.client_alive?
    refute status.supervisor_alive?
    refute status.transport_alive?
  end
end
