defmodule Core.Source do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Reference
  alias Core.Validators.DictionaryReference
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:report_origin, CodeableConcept)
    embeds_one(:asserter, Reference)
    embeds_one(:performer, Reference)
  end

  def changeset(%__MODULE__{} = source, params) do
    source
    |> cast(params, [])
    |> cast_embed(:report_origin)
    |> cast_embed(:asserter)
    |> cast_embed(:performer)
    |> validate_change(:report_origin, &DictionaryReference.validate_change/2)
  end

  def report_origin_performer_changeset(%__MODULE__{} = source, params, primary_source, client_id) do
    source
    |> cast(params, [])
    |> cast_embed(:report_origin)
    |> validate_performer(primary_source, client_id)
    |> validate_change(:report_origin, &DictionaryReference.validate_change/2)
  end

  def report_origin_asserter_changeset(%__MODULE__{} = source, params, primary_source, client_id) do
    source
    |> cast(params, [])
    |> cast_embed(:report_origin)
    |> validate_asserter(primary_source, client_id)
    |> validate_change(:report_origin, &DictionaryReference.validate_change/2)
  end

  defp validate_performer(changeset, true, client_id) do
    cast_embed(changeset, :performer,
      required: true,
      required_message: "performer must be present if primary_source is true",
      with:
        &Reference.employee_changeset(&1, &2,
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{get_in(&2, ~w(identifier value))} doesn't belong to your legal entity"
          ]
        )
    )
  end

  defp validate_performer(changeset, false, _) do
    cast_embed(changeset, :report_origin,
      required: true,
      required_message: "report_origin must be present if primary_source is false"
    )
  end

  defp validate_asserter(changeset, true, client_id) do
    cast_embed(changeset, :asserter,
      required: true,
      required_message: "asserter must be present if primary_source is true",
      with:
        &Reference.employee_changeset(&1, &2,
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{get_in(&2, ~w(identifier value))} doesn't belong to your legal entity"
          ]
        )
    )
  end

  defp validate_asserter(changeset, false, _) do
    cast_embed(changeset, :report_origin,
      required: true,
      required_message: "report_origin must be present if primary_source is false"
    )
  end
end
