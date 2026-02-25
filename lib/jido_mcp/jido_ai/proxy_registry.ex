defmodule Jido.MCP.JidoAI.ProxyRegistry do
  @moduledoc false

  use Agent

  @type proxy_entry :: %{
          required(:module) => module(),
          required(:local_name) => String.t(),
          required(:remote_name) => String.t(),
          required(:slot) => pos_integer()
        }

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{assignments: %{}, active: %{}} end, name: __MODULE__)
  end

  @spec assign_slots(atom(), [String.t()], pos_integer()) ::
          {:ok, %{required(String.t()) => pos_integer()}}
          | {:error, {:proxy_module_budget_exceeded, atom(), pos_integer()}}
          | {:error, :invalid_tool_names}
  def assign_slots(endpoint_id, remote_names, max_slots)
      when is_atom(endpoint_id) and is_list(remote_names) and is_integer(max_slots) and
             max_slots > 0 do
    remote_names = remote_names |> Enum.uniq() |> Enum.map(&normalize_remote_name/1)

    if Enum.any?(remote_names, &is_nil/1) do
      {:error, :invalid_tool_names}
    else
      Agent.get_and_update(__MODULE__, fn state ->
        endpoint_assignments = get_in(state, [:assignments, endpoint_id]) || %{}

        case allocate_slots(endpoint_assignments, remote_names, max_slots, endpoint_id) do
          {:ok, updated_assignments, slot_map} ->
            new_state = put_in(state, [:assignments, endpoint_id], updated_assignments)
            {{:ok, slot_map}, new_state}

          {:error, reason} ->
            {{:error, reason}, state}
        end
      end)
    end
  end

  @spec set_active(atom(), [proxy_entry()]) :: :ok
  def set_active(endpoint_id, entries) when is_atom(endpoint_id) and is_list(entries) do
    Agent.update(__MODULE__, &put_in(&1, [:active, endpoint_id], entries))
  end

  @spec active(atom()) :: [proxy_entry()]
  def active(endpoint_id) when is_atom(endpoint_id) do
    Agent.get(__MODULE__, &(get_in(&1, [:active, endpoint_id]) || []))
  end

  @spec clear_active(atom()) :: :ok
  def clear_active(endpoint_id) when is_atom(endpoint_id) do
    Agent.update(
      __MODULE__,
      &update_in(&1, [:active], fn active -> Map.delete(active, endpoint_id) end)
    )
  end

  @spec assignments(atom()) :: %{required(String.t()) => pos_integer()}
  def assignments(endpoint_id) when is_atom(endpoint_id) do
    Agent.get(__MODULE__, &(get_in(&1, [:assignments, endpoint_id]) || %{}))
  end

  @spec reset() :: :ok
  def reset do
    Agent.update(__MODULE__, fn _ -> %{assignments: %{}, active: %{}} end)
  end

  # Backward compatible wrappers
  @spec put(atom(), [module()]) :: :ok
  def put(endpoint_id, modules) when is_atom(endpoint_id) and is_list(modules) do
    entries =
      Enum.map(modules, fn module ->
        %{
          module: module,
          local_name: module.name(),
          remote_name: module.name(),
          slot: 0
        }
      end)

    set_active(endpoint_id, entries)
  end

  @spec get(atom()) :: [module()]
  def get(endpoint_id) when is_atom(endpoint_id) do
    endpoint_id
    |> active()
    |> Enum.map(& &1.module)
  end

  @spec delete(atom()) :: :ok
  def delete(endpoint_id) when is_atom(endpoint_id), do: clear_active(endpoint_id)

  defp normalize_remote_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_remote_name(_), do: nil

  defp allocate_slots(assignments, remote_names, max_slots, endpoint_id) do
    Enum.reduce_while(remote_names, {:ok, assignments, %{}}, fn remote_name,
                                                                {:ok, current, slot_map} ->
      case Map.fetch(current, remote_name) do
        {:ok, slot} ->
          {:cont, {:ok, current, Map.put(slot_map, remote_name, slot)}}

        :error ->
          used_slots = current |> Map.values() |> MapSet.new()

          case next_available_slot(used_slots, max_slots) do
            nil ->
              {:halt, {:error, {:proxy_module_budget_exceeded, endpoint_id, max_slots}}}

            slot ->
              updated = Map.put(current, remote_name, slot)
              {:cont, {:ok, updated, Map.put(slot_map, remote_name, slot)}}
          end
      end
    end)
  end

  defp next_available_slot(used_slots, max_slots) do
    1..max_slots
    |> Enum.find(&(not MapSet.member?(used_slots, &1)))
  end
end
