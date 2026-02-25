defmodule Jido.MCP.JidoAI.JSONSchemaToZoiTest do
  use ExUnit.Case, async: true

  alias Jido.MCP.JidoAI.JSONSchemaToZoi

  test "keeps schema keys as strings and supports nested defaults" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "repo-name" => %{"type" => "string"},
        "limit" => %{"type" => "integer", "default" => 10},
        "filters" => %{
          "type" => "object",
          "properties" => %{"label" => %{"type" => "string"}}
        }
      },
      "required" => ["repo-name"]
    }

    %{schema_ast: ast, warnings: []} = JSONSchemaToZoi.convert(schema)
    {zoi_schema, _bindings} = Code.eval_quoted(ast, [], __ENV__)

    assert {:ok, parsed} = Zoi.parse(zoi_schema, %{"repo-name" => "jido", "limit" => 5})
    assert parsed["repo-name"] == "jido"
    assert parsed["limit"] == 5
  end

  test "returns warning when root schema is not an object" do
    result = JSONSchemaToZoi.convert(%{"type" => "string"})

    assert result.warnings == ["root schema is not an object"]
  end

  test "handles nil and non-map schemas" do
    assert %{warnings: ["missing schema"]} = JSONSchemaToZoi.convert(nil)
    assert %{warnings: ["schema is not a map"]} = JSONSchemaToZoi.convert(:invalid)
  end
end
