defmodule Core.Validators.JsonSchema do
  @moduledoc """
  Validates JSON schema
  """

  use JValid
  use Confex, otp_app: :core
  alias Core.Validators.SchemaMapper

  use_schema(:visit_create, "json_schemas/visits/visit_create.json")
  use_schema(:visit_create_signed_content, "json_schemas/visits/visit_create_signed_content.json")
  use_schema(:episode_create, "json_schemas/episodes/episode_create.json")

  def validate(schema, attrs, errors_limit \\ nil) do
    result =
      @schemas
      |> Keyword.get(schema)
      |> SchemaMapper.prepare_schema(schema)
      |> validate_schema(attrs)

    case result do
      {:error, errors} -> {:error, limit_errors(errors, errors_limit)}
      :ok -> :ok
    end
  end

  defp limit_errors(errors, nil), do: Enum.take(errors, config()[:errors_limit])
  defp limit_errors(errors, limit), do: Enum.take(errors, limit)
end
