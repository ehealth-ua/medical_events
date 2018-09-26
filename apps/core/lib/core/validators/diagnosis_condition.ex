defmodule Core.Validators.DiagnosisCondition do
  @moduledoc false

  use Vex.Validator
  alias Core.Condition
  alias Core.Mongo
  alias Core.Patients

  def validate(value, options) do
    conditions = Keyword.get(options, :conditions)
    condition_ids = Enum.map(conditions, &Map.get(&1, :_id))
    patient_id = Keyword.get(options, :patient_id)

    if value in condition_ids do
      :ok
    else
      case Mongo.find_one(Condition.metadata().collection, %{
             "_id" => Mongo.string_to_uuid(value),
             "patient_id" => Patients.get_pk_hash(patient_id)
           }) do
        nil ->
          error(options, "Condition with such id is not found")

        _ ->
          :ok
      end
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
