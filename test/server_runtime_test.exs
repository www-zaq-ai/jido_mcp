defmodule Jido.MCP.Server.RuntimeTest do
  use ExUnit.Case, async: true

  alias Anubis.Server.Frame
  alias Jido.MCP.Server.Runtime

  defmodule AddAction do
    use Jido.Action,
      name: "add",
      schema: [
        a: [type: :integer, required: true],
        b: [type: :integer, required: true]
      ]

    @impl true
    def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
  end

  defmodule EchoResource do
    @behaviour Jido.MCP.Server.Resource

    @impl true
    def uri, do: "memo://echo"

    @impl true
    def name, do: "echo_resource"

    @impl true
    def description, do: "Echo resource"

    @impl true
    def mime_type, do: "application/json"

    @impl true
    def read(_uri, _frame), do: {:ok, %{ok: true}}
  end

  defmodule BasicPrompt do
    @behaviour Jido.MCP.Server.Prompt

    @impl true
    def name, do: "basic_prompt"

    @impl true
    def description, do: "Basic prompt"

    @impl true
    def arguments_schema, do: %{topic: {:required, :string}}

    @impl true
    def messages(args, _frame),
      do: {:ok, [%{"role" => "user", "content" => "Topic: #{args["topic"]}"}]}
  end

  defmodule AllowAllServer do
    def authorize(_request, _frame), do: :ok
  end

  defmodule DenyServer do
    def authorize(_request, _frame), do: :deny
  end

  defmodule ExplodingAuthorizeServer do
    def authorize(_request, _frame), do: raise("auth boom")
  end

  defmodule ExplodingResource do
    @behaviour Jido.MCP.Server.Resource

    @impl true
    def uri, do: "memo://boom"

    @impl true
    def name, do: "boom_resource"

    @impl true
    def description, do: "Boom resource"

    @impl true
    def mime_type, do: "application/json"

    @impl true
    def read(_uri, _frame), do: raise("resource boom")
  end

  defmodule ExplodingPrompt do
    @behaviour Jido.MCP.Server.Prompt

    @impl true
    def name, do: "boom_prompt"

    @impl true
    def description, do: "Boom prompt"

    @impl true
    def arguments_schema, do: %{}

    @impl true
    def messages(_args, _frame), do: raise("prompt boom")
  end

  defmodule InvalidPrompt do
    @behaviour Jido.MCP.Server.Prompt

    @impl true
    def name, do: "invalid_prompt"

    @impl true
    def description, do: "Invalid prompt"

    @impl true
    def arguments_schema, do: %{}

    @impl true
    def messages(_args, _frame), do: {:ok, %{not: :a_list}}
  end

  defmodule InvalidResource do
    @behaviour Jido.MCP.Server.Resource

    @impl true
    def uri, do: "memo://invalid"

    @impl true
    def name, do: "invalid_resource"

    @impl true
    def description, do: "Invalid resource"

    @impl true
    def mime_type, do: "application/json"

    @impl true
    def read(_uri, _frame), do: :not_valid
  end

  defmodule FailingAction do
    use Jido.Action,
      name: "failing",
      schema: [value: [type: :integer]]

    @impl true
    def run(_params, _context), do: {:error, :boom}
  end

  defmodule ZoiAction do
    use Jido.Action,
      name: "zoi_action",
      schema: Zoi.object(%{name: Zoi.string()})

    @impl true
    def run(%{name: name}, _context), do: {:ok, %{name: name}}
  end

  test "handles tool call through Jido action" do
    frame = Frame.new()

    assert {:reply, response, _frame} =
             Runtime.handle_tool_call([AddAction], "add", %{a: 2, b: 5}, frame, AllowAllServer)

    assert response.type == :tool
    assert response.structured_content == %{sum: 7}
  end

  test "handles resource read" do
    frame = Frame.new()

    assert {:reply, response, _frame} =
             Runtime.handle_resource_read(
               [EchoResource],
               EchoResource.uri(),
               frame,
               AllowAllServer
             )

    assert response.type == :resource
    assert response.contents["text"]
  end

  test "handles prompt get" do
    frame = Frame.new()

    assert {:reply, response, _frame} =
             Runtime.handle_prompt_get(
               [BasicPrompt],
               "basic_prompt",
               %{"topic" => "mcp"},
               frame,
               AllowAllServer
             )

    assert response.type == :prompt
    assert length(response.messages) == 1
  end

  test "rejects unauthorized tool call" do
    frame = Frame.new()

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_tool_call([AddAction], "add", %{a: 1, b: 2}, frame, DenyServer)
  end

  test "handles resource read exceptions with execution errors" do
    frame = Frame.new()

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_resource_read(
               [ExplodingResource],
               ExplodingResource.uri(),
               frame,
               AllowAllServer
             )
  end

  test "handles prompt rendering exceptions with execution errors" do
    frame = Frame.new()

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_prompt_get(
               [ExplodingPrompt],
               ExplodingPrompt.name(),
               %{},
               frame,
               AllowAllServer
             )
  end

  test "handles authorization exceptions with execution errors" do
    frame = Frame.new()

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_resource_read(
               [EchoResource],
               EchoResource.uri(),
               frame,
               ExplodingAuthorizeServer
             )
  end

  test "register_tool exports Zoi schema properties" do
    frame = Frame.new() |> Runtime.register_tool(ZoiAction)
    [tool] = Frame.get_tools(frame)

    properties = Map.get(tool.input_schema, "properties", %{})
    assert map_size(properties) > 0
  end

  test "returns not found errors for unknown components" do
    frame = Frame.new()

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_tool_call([AddAction], "missing", %{}, frame, AllowAllServer)

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_resource_read([EchoResource], "memo://missing", frame, AllowAllServer)

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_prompt_get([BasicPrompt], "missing", %{}, frame, AllowAllServer)
  end

  test "rejects unauthorized prompt and resource access" do
    frame = Frame.new()

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_prompt_get(
               [BasicPrompt],
               BasicPrompt.name(),
               %{},
               frame,
               DenyServer
             )

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_resource_read(
               [EchoResource],
               EchoResource.uri(),
               frame,
               DenyServer
             )
  end

  test "handles invalid prompt and resource return values" do
    frame = Frame.new()

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_prompt_get(
               [InvalidPrompt],
               InvalidPrompt.name(),
               %{},
               frame,
               AllowAllServer
             )

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Runtime.handle_resource_read(
               [InvalidResource],
               InvalidResource.uri(),
               frame,
               AllowAllServer
             )
  end

  test "handles action execution failures as tool errors" do
    frame = Frame.new()

    assert {:reply, response, _frame} =
             Runtime.handle_tool_call(
               [FailingAction],
               FailingAction.name(),
               %{value: 1},
               frame,
               AllowAllServer
             )

    assert response.type == :tool
    assert response.isError
  end
end
