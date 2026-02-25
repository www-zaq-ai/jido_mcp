defmodule Jido.MCP.AnubisClient do
  @moduledoc false

  # This module exists so Anubis.Client.Supervisor can derive child specs.
  use Anubis.Client,
    name: "JidoMCP",
    version: to_string(Application.spec(:jido_mcp, :vsn) || "0.1.1"),
    protocol_version: "2025-03-26",
    capabilities: []
end
