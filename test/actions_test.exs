defmodule Jido.MCP.ActionsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.MCP.Actions.{
    CallTool,
    GetPrompt,
    ListPrompts,
    ListResourceTemplates,
    ListResources,
    ListTools,
    ReadResource,
    RefreshEndpoint
  }

  setup :set_mimic_private
  setup :verify_on_exit!

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

  test "list actions forward options" do
    expect(Jido.MCP, :list_tools, fn :github, opts ->
      assert opts[:timeout] == 1_000
      assert opts[:cursor] == "a"
      {:ok, %{status: :ok}}
    end)

    expect(Jido.MCP, :list_resources, fn :github, opts ->
      assert opts[:timeout] == 1_100
      assert opts[:cursor] == "b"
      {:ok, %{status: :ok}}
    end)

    expect(Jido.MCP, :list_resource_templates, fn :github, opts ->
      assert opts[:timeout] == 1_200
      assert opts[:cursor] == "c"
      {:ok, %{status: :ok}}
    end)

    expect(Jido.MCP, :list_prompts, fn :github, opts ->
      assert opts[:timeout] == 1_300
      assert opts[:cursor] == "d"
      {:ok, %{status: :ok}}
    end)

    assert {:ok, _} =
             ListTools.run(%{timeout: 1_000, cursor: "a"}, %{default_endpoint: :github})

    assert {:ok, _} =
             ListResources.run(%{timeout: 1_100, cursor: "b"}, %{default_endpoint: :github})

    assert {:ok, _} =
             ListResourceTemplates.run(%{timeout: 1_200, cursor: "c"}, %{
               default_endpoint: :github
             })

    assert {:ok, _} =
             ListPrompts.run(%{timeout: 1_300, cursor: "d"}, %{default_endpoint: :github})
  end

  test "call, read, prompt, and refresh actions resolve endpoint ids" do
    expect(Jido.MCP, :call_tool, fn :github, "search", %{"q" => "bug"}, opts ->
      assert opts[:timeout] == 2_000
      {:ok, %{status: :ok}}
    end)

    expect(Jido.MCP, :read_resource, fn :github, "repo://README", opts ->
      assert opts[:timeout] == 2_100
      {:ok, %{status: :ok}}
    end)

    expect(Jido.MCP, :get_prompt, fn :github, "release", %{"v" => "1.0"}, opts ->
      assert opts[:timeout] == 2_200
      {:ok, %{status: :ok}}
    end)

    expect(Jido.MCP, :refresh_endpoint, fn :github ->
      {:ok, %{status: :ok}}
    end)

    assert {:ok, _} =
             CallTool.run(
               %{
                 endpoint_id: "github",
                 tool_name: "search",
                 arguments: %{"q" => "bug"},
                 timeout: 2_000
               },
               %{}
             )

    assert {:ok, _} =
             ReadResource.run(%{endpoint_id: "github", uri: "repo://README", timeout: 2_100}, %{})

    assert {:ok, _} =
             GetPrompt.run(
               %{
                 endpoint_id: "github",
                 prompt_name: "release",
                 arguments: %{"v" => "1.0"},
                 timeout: 2_200
               },
               %{}
             )

    assert {:ok, _} = RefreshEndpoint.run(%{endpoint_id: :github}, %{})
  end

  test "rejects unknown endpoint ids and disallowed endpoints" do
    assert {:error, :unknown_endpoint} =
             ListTools.run(%{endpoint_id: "unknown"}, %{})

    assert {:error, :endpoint_not_allowed} =
             ListTools.run(
               %{endpoint_id: :filesystem},
               %{allowed_endpoints: [:github]}
             )
  end

  test "list actions omit optional options when not provided" do
    expect(Jido.MCP, :list_tools, fn :github, [] -> {:ok, %{status: :ok}} end)
    expect(Jido.MCP, :list_resources, fn :github, [] -> {:ok, %{status: :ok}} end)
    expect(Jido.MCP, :list_resource_templates, fn :github, [] -> {:ok, %{status: :ok}} end)
    expect(Jido.MCP, :list_prompts, fn :github, [] -> {:ok, %{status: :ok}} end)

    assert {:ok, _} = ListTools.run(%{}, %{default_endpoint: :github})
    assert {:ok, _} = ListResources.run(%{}, %{default_endpoint: :github})
    assert {:ok, _} = ListResourceTemplates.run(%{}, %{default_endpoint: :github})
    assert {:ok, _} = ListPrompts.run(%{}, %{default_endpoint: :github})
  end
end
