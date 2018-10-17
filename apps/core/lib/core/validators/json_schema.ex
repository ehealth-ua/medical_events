defmodule Core.Validators.JsonSchema do
  @moduledoc """
  Validates JSON schema
  """

  use JValid
  use Confex, otp_app: :core
  alias Core.Validators.SchemaMapper

  use_schema(:package_create, "json_schemas/packages/package_create.json")
  use_schema(:package_create_signed_content, "json_schemas/packages/package_create_signed_content.json")
  use_schema(:package_cancel, "json_schemas/packages/package_cancel.json")
  use_schema(:package_cancel_signed_content, "json_schemas/packages/package_cancel_signed_content.json")
  use_schema(:episode_create, "json_schemas/episodes/episode_create.json")
  use_schema(:episode_update, "json_schemas/episodes/episode_update.json")
  use_schema(:episode_close, "json_schemas/episodes/episode_close.json")
  use_schema(:episode_cancel, "json_schemas/episodes/episode_cancel.json")
  use_schema(:episode_get, "json_schemas/episodes/episode_get.json")
  use_schema(:condition_request, "json_schemas/conditions/condition_request.json")
  use_schema(:condition_summary, "json_schemas/conditions/condition_summary.json")
  use_schema(:allergy_intolerance_request, "json_schemas/allergy_intolerances/allergy_intolerance_request.json")
  use_schema(:allergy_intolerance_summary, "json_schemas/allergy_intolerances/allergy_intolerance_summary.json")
  use_schema(:immunization_request, "json_schemas/immunizations/immunization_request.json")
  use_schema(:immunization_summary, "json_schemas/immunizations/immunization_summary.json")

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
