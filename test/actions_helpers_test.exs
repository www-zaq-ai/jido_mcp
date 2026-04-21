defmodule Jido.MCP.Actions.HelpersTest do
  use ExUnit.Case, async: false

  alias Jido.MCP
  alias Jido.MCP.Actions.Helpers
  alias Jido.MCP.Endpoint

  setup do
    previous = Application.get_env(:jido_mcp, :endpoints)
    previous_runtime_endpoints = Application.get_env(:jido_mcp, :runtime_endpoints)
    previous_runtime_removed = Application.get_env(:jido_mcp, :runtime_removed_endpoints)

    Application.delete_env(:jido_mcp, :runtime_endpoints)
    Application.delete_env(:jido_mcp, :runtime_removed_endpoints)

    Application.put_env(:jido_mcp, :endpoints, %{
      github: %{
        transport: {:streamable_http, [base_url: "http://localhost:3000/mcp"]},
        client_info: %{name: "my_app"}
      },
      filesystem: %{
        transport: {:stdio, [command: "echo"]},
        client_info: %{name: "my_app"}
      }
    })

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:jido_mcp, :endpoints)
      else
        Application.put_env(:jido_mcp, :endpoints, previous)
      end

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

  test "allows all configured endpoints when allowed_endpoints is :all" do
    context = %{allowed_endpoints: :all}

    assert {:ok, :github} = Helpers.resolve_endpoint_id(%{endpoint_id: :github}, context)
    assert {:ok, :filesystem} = Helpers.resolve_endpoint_id(%{endpoint_id: :filesystem}, context)
  end

  test "returns unknown endpoint for unconfigured endpoint names" do
    assert {:error, :unknown_endpoint} =
             Helpers.resolve_endpoint_id(%{endpoint_id: :missing}, %{})

    assert {:error, :unknown_endpoint} =
             Helpers.resolve_endpoint_id(%{endpoint_id: "missing"}, %{})
  end

  test "resolves runtime-registered endpoints" do
    {:ok, endpoint} =
      Endpoint.new(:runtime_demo, %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "runtime"}
      })

    assert :ok = MCP.register_endpoint(endpoint)

    on_exit(fn ->
      _ = MCP.unregister_endpoint(:runtime_demo)
    end)

    assert {:ok, :runtime_demo} = Helpers.resolve_endpoint_id(%{endpoint_id: :runtime_demo}, %{})
    assert {:ok, :runtime_demo} = Helpers.resolve_endpoint_id(%{endpoint_id: "runtime_demo"}, %{})

    assert :ok = MCP.unregister_endpoint(:runtime_demo)

    assert {:error, :unknown_endpoint} =
             Helpers.resolve_endpoint_id(%{endpoint_id: :runtime_demo}, %{})
  end
end
