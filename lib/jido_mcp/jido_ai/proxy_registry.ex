defmodule Jido.MCP.JidoAI.ProxyRegistry do
  @moduledoc false

  use Agent

  @type agent_identity :: {:pid, pid()} | {:name, term()}
  @type registry_key :: {agent_identity(), atom()}

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec put(term(), atom(), [module()]) :: :ok
  def put(agent_server, endpoint_id, modules)
      when is_atom(endpoint_id) and is_list(modules) do
    key = key_for(agent_server, endpoint_id)
    Agent.update(__MODULE__, &Map.put(&1, key, modules))
  end

  @spec get(term(), atom()) :: [module()]
  def get(agent_server, endpoint_id) when is_atom(endpoint_id) do
    key = key_for(agent_server, endpoint_id)
    Agent.get(__MODULE__, &Map.get(&1, key, []))
  end

  @spec delete(term(), atom()) :: [module()]
  def delete(agent_server, endpoint_id) when is_atom(endpoint_id) do
    key = key_for(agent_server, endpoint_id)

    Agent.get_and_update(__MODULE__, fn state ->
      {Map.get(state, key, []), Map.delete(state, key)}
    end)
  end

  @spec module_in_use?(module()) :: boolean()
  def module_in_use?(module) when is_atom(module) do
    Agent.get(__MODULE__, fn state ->
      Enum.any?(state, fn {_key, modules} -> module in modules end)
    end)
  end

  @spec key_for(term(), atom()) :: registry_key()
  def key_for(agent_server, endpoint_id) when is_atom(endpoint_id) do
    {agent_identity(agent_server), endpoint_id}
  end

  @spec agent_identity(term()) :: agent_identity()
  def agent_identity(agent_server) when is_pid(agent_server), do: {:pid, agent_server}
  def agent_identity(agent_server), do: {:name, agent_server}

  @spec entries() :: %{optional(registry_key()) => [module()]}
  def entries do
    Agent.get(__MODULE__, & &1)
  end
end
