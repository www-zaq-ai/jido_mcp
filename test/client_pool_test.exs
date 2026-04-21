defmodule Jido.MCP.ClientPoolTest do
  use ExUnit.Case, async: false

  alias Jido.MCP.{ClientPool, Endpoint}

  setup do
    previous_runtime_endpoints = Application.get_env(:jido_mcp, :runtime_endpoints)
    previous_runtime_removed = Application.get_env(:jido_mcp, :runtime_removed_endpoints)

    Application.delete_env(:jido_mcp, :runtime_endpoints)
    Application.delete_env(:jido_mcp, :runtime_removed_endpoints)

    {:ok, endpoint} =
      Endpoint.new(:github, %{
        transport: {:streamable_http, [base_url: "http://localhost:3000/mcp"]},
        client_info: %{name: "my_app"}
      })

    :sys.replace_state(ClientPool, fn _ ->
      %{
        endpoints: %{github: endpoint},
        refs: %{}
      }
    end)

    on_exit(fn ->
      if is_nil(previous_runtime_endpoints) do
        Application.delete_env(:jido_mcp, :runtime_endpoints)
      else
        Application.put_env(:jido_mcp, :runtime_endpoints, previous_runtime_endpoints)
      end

      if is_nil(previous_runtime_removed) do
        Application.delete_env(:jido_mcp, :runtime_removed_endpoints)
      else
        Application.put_env(:jido_mcp, :runtime_removed_endpoints, previous_runtime_removed)
      end
    end)

    :ok
  end

  test "returns unknown endpoint when endpoint id is missing from pool state" do
    assert {:error, :unknown_endpoint} = ClientPool.ensure_client(:missing)
    assert {:error, :unknown_endpoint} = ClientPool.refresh(:missing)
  end

  test "registers a new endpoint and rejects duplicates" do
    {:ok, local_fs} =
      Endpoint.new(:local_fs, %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "my_app"}
      })

    assert :ok = ClientPool.register_endpoint(local_fs)
    assert {:ok, endpoints} = ClientPool.endpoints()
    assert %Endpoint{id: :local_fs} = endpoints.local_fs

    assert {:error, :duplicate_endpoint} = ClientPool.register_endpoint(local_fs)
  end

  test "unregister removes endpoint and rejects unknown endpoint" do
    assert :ok = ClientPool.unregister_endpoint(:github)
    assert {:ok, endpoints} = ClientPool.endpoints()
    refute Map.has_key?(endpoints, :github)
    assert {:error, :unknown_endpoint} = ClientPool.ensure_client(:github)
    assert {:error, :unknown_endpoint} = ClientPool.unregister_endpoint(:github)
  end

  test "supports endpoint replacement via unregister then register" do
    assert :ok = ClientPool.unregister_endpoint(:github)

    {:ok, github} =
      Endpoint.new(:github, %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "my_app"},
        timeouts: %{request_ms: 9_999}
      })

    assert :ok = ClientPool.register_endpoint(github)
    assert {:ok, endpoints} = ClientPool.endpoints()
    assert endpoints.github.timeouts.request_ms == 9_999
  end

  test "returns not_started status before endpoint client is initialized" do
    assert {:error, :not_started} = ClientPool.endpoint_status(:github)
  end

  test "reports liveness flags for tracked refs" do
    :sys.replace_state(ClientPool, fn state ->
      put_in(state, [:refs, :github], %{
        client: :nonexistent_client_name,
        supervisor: :nonexistent_supervisor_name,
        transport: :nonexistent_transport_name
      })
    end)

    assert {:ok, status} = ClientPool.endpoint_status(:github)
    refute status.client_alive?
    refute status.supervisor_alive?
    refute status.transport_alive?
  end
end
