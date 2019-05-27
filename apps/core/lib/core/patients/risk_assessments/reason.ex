defmodule Core.Patients.RiskAssessments.Reason do
  @moduledoc false

  use Ecto.Schema
  alias Core.CodeableConcept
  alias Core.Reference
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_many(:reason_codes, CodeableConcept)
    embeds_many(:reason_references, Reference)
  end

  def changeset(%__MODULE__{} = reason, params) do
    reason
    |> cast(params, [])
    |> cast_embed(:reason_codes)
    |> cast_embed(:reason_references)
  end

  def encounter_package_changeset(
        %__MODULE__{} = reason,
        params,
        patient_id_hash,
        observations,
        conditions,
        diagnostic_reports
      ) do
    reason
    |> cast(params, [])
    |> cast_embed(:reason_codes)
    |> cast_embed(
      :reason_references,
      with:
        &Reference.reason_reference_changeset(&1, &2,
          patient_id_hash: patient_id_hash,
          observarvations: observations,
          conditions: conditions,
          diagnostic_reports: diagnostic_reports
        )
    )
  end
end
