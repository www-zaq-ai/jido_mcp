defmodule Jido.MCP.ConfigTest do
  use ExUnit.Case, async: false

  alias Jido.MCP.Config

  defmodule EndpointLoader do
    def valid_endpoints do
      %{
        github: %{
          transport: {:stdio, [command: "cat", args: []]},
          client_info: %{name: "loader_app"}
        }
      }
    end

    def invalid_endpoints, do: :invalid
  end

  setup do
    previous = Application.get_env(:jido_mcp, :endpoints)

    Application.put_env(:jido_mcp, :endpoints, %{
      github: %{
        transport: {:streamable_http, [base_url: "http://localhost:3000/mcp"]},
        client_info: %{name: "my_app"}
      }
    })

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:jido_mcp, :endpoints)
      else
        Application.put_env(:jido_mcp, :endpoints, previous)
      end
    end)

    :ok
  end

  test "resolve_endpoint_id supports known atoms and strings only" do
    assert {:ok, :github} = Config.resolve_endpoint_id(:github)
    assert {:ok, :github} = Config.resolve_endpoint_id("github")
    assert {:ok, _endpoint} = Config.fetch_endpoint(:github)
    assert {:error, :unknown_endpoint} = Config.resolve_endpoint_id(:missing)
    assert {:error, :unknown_endpoint} = Config.resolve_endpoint_id("missing")
    assert {:error, :unknown_endpoint} = Config.fetch_endpoint(:missing)
    assert {:error, :endpoint_required} = Config.resolve_endpoint_id(nil)
  end

  test "normalize_endpoints rejects binary endpoint ids" do
    assert_raise ArgumentError, ~r/endpoint keys must be atoms/, fn ->
      Config.normalize_endpoints(%{
        "github" => %{
          transport: {:streamable_http, [base_url: "http://localhost:3000/mcp"]},
          client_info: %{name: "my_app"}
        }
      })
    end
  end

  test "loads endpoints from an MFA callback" do
    Application.put_env(:jido_mcp, :endpoints, {EndpointLoader, :valid_endpoints, []})

    assert %{github: endpoint} = Config.endpoints()
    assert endpoint.id == :github
    assert endpoint.client_info["name"] == "loader_app"
  end

  test "raises when endpoints MFA callback returns invalid data" do
    Application.put_env(:jido_mcp, :endpoints, {EndpointLoader, :invalid_endpoints, []})

    assert_raise ArgumentError, ~r/MFA callback return/, fn ->
      Config.endpoints()
    end
  end
end
