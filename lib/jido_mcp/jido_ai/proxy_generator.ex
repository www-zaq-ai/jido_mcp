defmodule Jido.MCP.JidoAI.ProxyGenerator do
  @moduledoc false

  alias Jido.MCP.JidoAI.JSONSchemaToZoi

  @type proxy_entry :: %{
          required(:module) => module(),
          required(:local_name) => String.t(),
          required(:remote_name) => String.t(),
          required(:slot) => pos_integer()
        }

  @spec build_modules(atom(), [map()], keyword()) ::
          {:ok, [proxy_entry()], %{String.t() => [String.t()]}} | {:error, term()}
  def build_modules(endpoint_id, tools, opts \\ [])
      when is_atom(endpoint_id) and is_list(tools) do
    prefix = Keyword.get(opts, :prefix, "mcp_#{endpoint_id}_")
    slot_map = Keyword.get(opts, :slot_map, %{})

    Enum.reduce_while(tools, {:ok, [], %{}}, fn tool, {:ok, entries, warning_acc} ->
      with name when is_binary(name) <- Map.get(tool, "name"),
           name <- String.trim(name),
           false <- name == "",
           slot when is_integer(slot) and slot > 0 <- Map.get(slot_map, name),
           module <- module_name(endpoint_id, slot),
           local_name <- local_tool_name(prefix, name, slot),
           description <- Map.get(tool, "description") || "MCP proxy tool #{name}",
           %{schema_ast: schema_ast, warnings: schema_warnings} <-
             JSONSchemaToZoi.convert(Map.get(tool, "inputSchema")),
           {:ok, module} <-
             ensure_proxy_module(
               module,
               endpoint_id,
               name,
               local_name,
               description,
               schema_ast,
               slot
             ) do
        warning_acc =
          if schema_warnings == [],
            do: warning_acc,
            else: Map.put(warning_acc, local_name, schema_warnings)

        entry = %{module: module, local_name: local_name, remote_name: name, slot: slot}
        {:cont, {:ok, [entry | entries], warning_acc}}
      else
        {:error, reason} ->
          {:halt, {:error, reason}}

        true ->
          {:cont, {:ok, entries, warning_acc}}

        _ ->
          {:cont, {:ok, entries, warning_acc}}
      end
    end)
    |> case do
      {:ok, entries, warnings} -> {:ok, Enum.reverse(entries), warnings}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_proxy_module(
         module,
         endpoint_id,
         remote_name,
         local_name,
         description,
         schema_ast,
         slot
       )
       when is_atom(module) do
    if Code.ensure_loaded?(module) do
      case proxy_info(module) do
        %{
          endpoint_id: ^endpoint_id,
          remote_tool_name: ^remote_name,
          local_name: ^local_name,
          slot: ^slot
        } ->
          {:ok, module}

        %{remote_tool_name: other_remote_name} ->
          {:error, {:proxy_module_slot_conflict, module, remote_name, other_remote_name}}

        _ ->
          {:ok, module}
      end
    else
      create_proxy_module(
        module,
        endpoint_id,
        remote_name,
        local_name,
        description,
        schema_ast,
        slot
      )
    end
  end

  defp proxy_info(module) do
    if function_exported?(module, :__mcp_proxy__, 0), do: module.__mcp_proxy__(), else: %{}
  end

  defp create_proxy_module(
         module,
         endpoint_id,
         remote_name,
         local_name,
         description,
         schema_ast,
         slot
       ) do
    quoted =
      quote location: :keep do
        use Jido.Action,
          name: unquote(local_name),
          description: unquote(description),
          schema: unquote(schema_ast)

        @endpoint_id unquote(endpoint_id)
        @remote_tool_name unquote(remote_name)
        @local_name unquote(local_name)
        @slot unquote(slot)

        @impl true
        def run(params, _context) do
          case Jido.MCP.call_tool(@endpoint_id, @remote_tool_name, params) do
            {:ok, %{data: data}} -> {:ok, data}
            {:error, error} -> {:error, error}
          end
        end

        def __mcp_proxy__ do
          %{
            endpoint_id: @endpoint_id,
            remote_tool_name: @remote_tool_name,
            local_name: @local_name,
            slot: @slot
          }
        end
      end

    {:module, created, _bytecode, _result} =
      Module.create(module, quoted, Macro.Env.location(__ENV__))

    {:ok, created}
  end

  defp module_name(endpoint_id, slot) do
    endpoint = endpoint_id |> Atom.to_string() |> Macro.camelize()
    Module.concat([Jido, MCP, JidoAI, Proxy, endpoint, "Slot#{slot}"])
  end

  defp local_tool_name(prefix, remote_name, slot) do
    "#{prefix}#{sanitize_segment(remote_name)}__#{slot}"
  end

  defp sanitize_segment(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "tool"
      normalized -> normalized
    end
  end
end
