defmodule Jido.MCP.ConfigTest do
  use ExUnit.Case, async: false

  alias Jido.MCP.Config

  setup do
    original = Application.get_env(:jido_mcp, :endpoints)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_mcp, :endpoints)
      else
        Application.put_env(:jido_mcp, :endpoints, original)
      end
    end)

    :ok
  end

  test "normalizes valid endpoint map and exposes ids" do
    Application.put_env(:jido_mcp, :endpoints, %{
      github: %{
        transport: {:streamable_http, [base_url: "http://localhost:4001/mcp"]},
        client_info: %{name: "test"}
      },
      filesystem: %{
        transport: {:stdio, [command: "cat", args: []]},
        client_info: %{name: "test"}
      }
    })

    endpoints = Config.endpoints()
    assert Map.has_key?(endpoints, :github)
    assert Map.has_key?(endpoints, :filesystem)
    assert [:filesystem, :github] == Config.endpoint_ids()

    assert {:ok, _endpoint} = Config.fetch_endpoint(:github)
    assert {:error, :unknown_endpoint} = Config.fetch_endpoint(:missing)
  end

  test "rejects non-atom endpoint keys" do
    assert_raise ArgumentError, ~r/endpoint keys must be atoms/, fn ->
      Config.normalize_endpoints(%{
        "github" => %{
          transport: {:stdio, [command: "cat", args: []]},
          client_info: %{name: "test"}
        }
      })
    end
  end

  test "normalizes keyword endpoints and invalid container values" do
    endpoints =
      Config.normalize_endpoints(
        github: %{
          transport: {:stdio, [command: "cat", args: []]},
          client_info: %{name: "test"}
        }
      )

    assert Map.has_key?(endpoints, :github)
    assert %{} == Config.normalize_endpoints(:invalid)
  end
end
