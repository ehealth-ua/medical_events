defmodule Core.Validators.JsonSchema do
  @moduledoc """
  Validates JSON schema
  """

  use JValid
  alias Core.Validators.SchemaMapper

  use_schema(:visit_create, "json_schemas/visits/visit_create.json")
  use_schema(:visit_create_signed_content, "json_schemas/visits/visit_create_signed_content.json")

  def validate(schema, attrs) do
    @schemas
    |> Keyword.get(schema)
    |> SchemaMapper.prepare_schema(schema)
    |> validate_schema(attrs)
  end
end
