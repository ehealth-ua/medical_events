defmodule Core.Validators.EncounterReference do
  @moduledoc false

  use Vex.Validator
  alias Core.Encounter
  alias Core.Patients.Encounters

  @status_entered_in_error Encounter.status(:entered_in_error)

  def validate(encounter_id, options) do
    patient_id_hash = Keyword.get(options, :patient_id_hash)

    case Encounters.get_by_id(patient_id_hash, encounter_id) do
      nil ->
        error(options, "Encounter with such id is not found")

      {:ok, %{status: @status_entered_in_error}} ->
        error(options, ~s(Encounter in "entered_in_error" status can not be referenced))

      _ ->
        :ok
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
