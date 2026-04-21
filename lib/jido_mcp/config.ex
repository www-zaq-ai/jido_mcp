defmodule Jido.MCP.Config do
  @moduledoc """
  Loads and validates application MCP endpoint configuration.
  """

  alias Jido.MCP.{Endpoint, EndpointID}

  @runtime_endpoints_key :runtime_endpoints
  @runtime_removed_endpoints_key :runtime_removed_endpoints

  @type endpoints :: %{required(atom()) => Endpoint.t()}
  @type endpoint_id_error :: :endpoint_required | :invalid_endpoint_id | :unknown_endpoint

  @spec endpoints() :: endpoints()
  def endpoints do
    configured_endpoints =
      :jido_mcp
      |> Application.get_env(:endpoints, %{})
      |> resolve_endpoints_source!()
      |> normalize_endpoints()

    runtime_endpoints =
      :jido_mcp
      |> Application.get_env(@runtime_endpoints_key, %{})
      |> normalize_endpoints()

    removed_ids =
      :jido_mcp
      |> Application.get_env(@runtime_removed_endpoints_key, [])
      |> Enum.filter(&is_atom/1)

    configured_endpoints
    |> Map.drop(removed_ids)
    |> Map.merge(runtime_endpoints)
  end

  @spec active_endpoints() :: endpoints()
  def active_endpoints do
    endpoints()
  end

  @spec register_runtime_endpoint(Endpoint.t()) :: :ok
  def register_runtime_endpoint(%Endpoint{} = endpoint) do
    runtime_endpoints = Application.get_env(:jido_mcp, @runtime_endpoints_key, %{})
    removed_ids = Application.get_env(:jido_mcp, @runtime_removed_endpoints_key, [])

    Application.put_env(
      :jido_mcp,
      @runtime_endpoints_key,
      Map.put(runtime_endpoints, endpoint.id, endpoint)
    )

    Application.put_env(
      :jido_mcp,
      @runtime_removed_endpoints_key,
      Enum.reject(removed_ids, &(&1 == endpoint.id))
    )

    :ok
  end

  @spec unregister_runtime_endpoint(atom()) :: :ok
  def unregister_runtime_endpoint(endpoint_id) when is_atom(endpoint_id) do
    runtime_endpoints = Application.get_env(:jido_mcp, @runtime_endpoints_key, %{})
    removed_ids = Application.get_env(:jido_mcp, @runtime_removed_endpoints_key, [])

    Application.put_env(
      :jido_mcp,
      @runtime_endpoints_key,
      Map.delete(runtime_endpoints, endpoint_id)
    )

    Application.put_env(
      :jido_mcp,
      @runtime_removed_endpoints_key,
      Enum.uniq([endpoint_id | removed_ids])
    )

    :ok
  end

  @spec fetch_endpoint(atom()) :: {:ok, Endpoint.t()} | {:error, :unknown_endpoint}
  def fetch_endpoint(endpoint_id) when is_atom(endpoint_id) do
    case Map.fetch(active_endpoints(), endpoint_id) do
      {:ok, endpoint} -> {:ok, endpoint}
      :error -> {:error, :unknown_endpoint}
    end
  end

  @spec endpoint_ids() :: [atom()]
  def endpoint_ids do
    active_endpoints()
    |> Map.keys()
    |> Enum.sort()
  end

  @spec resolve_endpoint_id(term(), endpoints()) :: {:ok, atom()} | {:error, endpoint_id_error()}
  def resolve_endpoint_id(endpoint_id, endpoints \\ active_endpoints()) do
    EndpointID.resolve(endpoint_id, endpoints)
  end

  @spec normalize_endpoints(map() | keyword()) :: endpoints()
  def normalize_endpoints(endpoints) when is_list(endpoints) do
    endpoints
    |> Enum.into(%{})
    |> normalize_endpoints()
  end

  def normalize_endpoints(endpoints) when is_map(endpoints) do
    Enum.reduce(endpoints, %{}, fn {id, attrs}, acc ->
      id = normalize_id!(id)

      case attrs do
        %Endpoint{id: ^id} = endpoint ->
          Map.put(acc, id, endpoint)

        %Endpoint{id: other_id} ->
          raise ArgumentError,
                "Invalid endpoint #{inspect(id)}: endpoint struct id #{inspect(other_id)} does not match key"

        _ ->
          case Endpoint.new(id, attrs) do
            {:ok, endpoint} ->
              Map.put(acc, id, endpoint)

            {:error, reason} ->
              raise ArgumentError, "Invalid endpoint #{inspect(id)}: #{inspect(reason)}"
          end
      end
    end)
  end

  def normalize_endpoints(_), do: %{}

  defp resolve_endpoints_source!({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    endpoints =
      try do
        apply(module, function, args)
      rescue
        exception ->
          raise ArgumentError,
                "Invalid :jido_mcp, :endpoints MFA callback #{inspect({module, function, args})}: #{Exception.message(exception)}"
      catch
        kind, reason ->
          raise ArgumentError,
                "Invalid :jido_mcp, :endpoints MFA callback #{inspect({module, function, args})}: #{inspect({kind, reason})}"
      end

    if is_map(endpoints) or is_list(endpoints) do
      endpoints
    else
      raise ArgumentError,
            "Invalid :jido_mcp, :endpoints MFA callback return #{inspect(endpoints)}: expected map or keyword"
    end
  end

  defp resolve_endpoints_source!(value), do: value

  defp normalize_id!(id) when is_atom(id), do: id

  defp normalize_id!(id) do
    raise ArgumentError, "Invalid endpoint id #{inspect(id)}: endpoint keys must be atoms"
  end
end
