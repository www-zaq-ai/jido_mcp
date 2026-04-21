defmodule Jido.MCP.EndpointID do
  @moduledoc false

  alias Jido.MCP.Config

  @type resolve_error :: :endpoint_required | :invalid_endpoint_id | :unknown_endpoint

  @spec resolve(term()) :: {:ok, atom()} | {:error, resolve_error()}
  def resolve(value), do: resolve(value, Config.active_endpoints())

  @spec resolve(term(), map()) :: {:ok, atom()} | {:error, resolve_error()}
  def resolve(nil, _endpoints), do: {:error, :endpoint_required}

  def resolve(endpoint_id, endpoints) when is_atom(endpoint_id) and is_map(endpoints) do
    if Map.has_key?(endpoints, endpoint_id),
      do: {:ok, endpoint_id},
      else: {:error, :unknown_endpoint}
  end

  def resolve(endpoint_id, endpoints) when is_binary(endpoint_id) and is_map(endpoints) do
    endpoint_id = String.trim(endpoint_id)

    cond do
      endpoint_id == "" ->
        {:error, :invalid_endpoint_id}

      true ->
        case Enum.find(Map.keys(endpoints), &(Atom.to_string(&1) == endpoint_id)) do
          nil -> {:error, :unknown_endpoint}
          id -> {:ok, id}
        end
    end
  end

  def resolve(_endpoint_id, _endpoints), do: {:error, :invalid_endpoint_id}
end
