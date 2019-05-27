defmodule Core.Patient do
  @moduledoc false

  use Ecto.Schema
  alias Core.AllergyIntolerance
  alias Core.Device
  alias Core.DiagnosticReport
  alias Core.Ecto.UUID, as: U
  alias Core.Encounter
  alias Core.Episode
  alias Core.Immunization
  alias Core.MedicationStatement
  alias Core.RiskAssessment
  alias Core.Visit

  @status_active "active"
  @status_inactive "inactive"

  def status(:active), do: @status_active
  def status(:inactive), do: @status_inactive

  def collection, do: "patients"

  @primary_key {:_id, :binary_id, autogenerate: false}
  schema "patients" do
    field(:status, :string)
    field(:inserted_by, U)
    field(:updated_by, U)

    embeds_many(:visits, Visit)
    embeds_many(:episodes, Episode)
    embeds_many(:encounters, Encounter)
    embeds_many(:immunizations, Immunization)
    embeds_many(:allergy_intolerances, AllergyIntolerance)
    embeds_many(:risk_assessments, RiskAssessment)
    embeds_many(:devices, Device)
    embeds_many(:medication_statements, MedicationStatement)
    embeds_many(:diagnostic_reports, DiagnosticReport)

    timestamps(type: :utc_datetime_usec)
  end
end
