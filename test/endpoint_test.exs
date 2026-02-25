defmodule Jido.MCP.EndpointTest do
  use ExUnit.Case, async: true

  alias Jido.MCP.Endpoint

  test "builds endpoint with defaults" do
    assert {:ok, endpoint} =
             Endpoint.new(:github, %{
               transport: {:streamable_http, base_url: "http://localhost:3000/mcp"},
               client_info: %{name: "my_app", version: "1.0.0"}
             })

    assert endpoint.id == :github
    assert endpoint.protocol_version == "2025-03-26"
    assert endpoint.timeouts.request_ms == 30_000
    assert endpoint.capabilities == %{}
  end

  test "rejects invalid transport" do
    assert {:error, {:invalid_transport, _, _}} =
             Endpoint.new(:bad, %{
               transport: {:websocket, url: "ws://localhost:3000/mcp"},
               client_info: %{name: "my_app"}
             })
  end

  test "rejects invalid client info and timeout values" do
    assert {:error, {:invalid_client_info, _, _}} =
             Endpoint.new(:bad_client, %{
               transport: {:stdio, [command: "cat", args: []]},
               client_info: %{}
             })

    assert {:error, {:invalid_timeouts, _, _}} =
             Endpoint.new(:bad_timeout, %{
               transport: {:stdio, [command: "cat", args: []]},
               client_info: %{name: "my_app"},
               timeouts: %{request_ms: 0}
             })
  end

  test "supports string-keyed attrs" do
    assert {:ok, endpoint} =
             Endpoint.new(:string_keys, %{
               "transport" => {:stdio, [command: "cat", args: []]},
               "client_info" => %{"name" => "my_app", "version" => "2"},
               "protocol_version" => "2025-03-26",
               "capabilities" => %{"tools" => true},
               "timeouts" => %{"request_ms" => 1234}
             })

    assert endpoint.client_info == %{"name" => "my_app", "version" => "2"}
    assert endpoint.capabilities == %{"tools" => true}
    assert endpoint.timeouts.request_ms == 1234
  end

  test "rejects invalid protocol version and capabilities" do
    assert {:error, {:invalid_protocol_version, _, _}} =
             Endpoint.new(:bad_protocol, %{
               transport: {:stdio, [command: "cat", args: []]},
               client_info: %{name: "my_app"},
               protocol_version: 123
             })

    assert {:error, {:invalid_capabilities, _, _}} =
             Endpoint.new(:bad_capabilities, %{
               transport: {:stdio, [command: "cat", args: []]},
               client_info: %{name: "my_app"},
               capabilities: :invalid
             })
  end

  test "rejects invalid timeout container" do
    assert {:error, {:invalid_timeouts, _, _}} =
             Endpoint.new(:bad_timeout_container, %{
               transport: {:stdio, [command: "cat", args: []]},
               client_info: %{name: "my_app"},
               timeouts: :invalid
             })
  end
end
