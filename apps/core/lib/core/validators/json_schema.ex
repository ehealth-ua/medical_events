defmodule Core.Validators.JsonSchema do
  @moduledoc """
  Validates JSON schema
  """

  use JValid
  alias Core.Validators.SchemaMapper

  use_schema(:visit_create, "json_schemas/visits/visit_create.json")

  def validate(schema, attrs) do
    @schemas
    |> Keyword.get(schema)
    |> SchemaMapper.prepare_schema(schema)
    |> validate_schema(attrs)
  end
end
