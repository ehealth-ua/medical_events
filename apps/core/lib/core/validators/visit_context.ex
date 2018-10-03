defmodule Core.Validators.VisitContext do
  @moduledoc false

  use Vex.Validator
  alias Core.Mongo
  alias Core.Patient
  alias Core.Visit

  def validate(visit_id, options) do
    visit = Keyword.get(options, :visit)
    patient_id_hash = Keyword.get(options, :patient_id_hash)
    validate_visit(visit_id, visit, patient_id_hash, options)
  end

  defp validate_visit(visit_id, %Visit{id: id}, _, options) do
    if visit_id == id do
      :ok
    else
      error(options, "Visit with such ID is not found")
    end
  end

  defp validate_visit(visit_id, nil, patient_id_hash, options) do
    result =
      Patient.metadata().collection
      |> Mongo.aggregate([
        %{"$match" => %{"_id" => patient_id_hash}},
        %{"$project" => %{"_id" => "$visits.#{visit_id}.id"}}
      ])
      |> Enum.to_list()

    case result do
      [%{"_id" => _}] ->
        :ok

      _ ->
        error(options, "Visit with such ID is not found")
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
