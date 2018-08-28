defmodule Core.Validators.VisitContext do
  @moduledoc false

  use Vex.Validator
  alias Core.Mongo
  alias Core.Patient
  alias Core.Visit

  def validate(visit_id, options) do
    visit = Keyword.get(options, :visit)
    patient_id = Keyword.get(options, :patient_id)
    validate_visit(visit_id, visit, patient_id, options)
  end

  defp validate_visit(visit_id, %Visit{id: id}, _, options) do
    if visit_id == id do
      :ok
    else
      error(options, "Visit with such ID is not found")
    end
  end

  defp validate_visit(visit_id, nil, patient_id, options) do
    result =
      Patient.metadata().collection
      |> Mongo.aggregate([
        %{"$match" => %{"_id" => patient_id}},
        %{"$project" => %{"_id" => "$visits.#{visit_id}.id"}}
      ])
      |> Enum.to_list()

    case result do
      [%{"_id" => _}] ->
        error(options, "Visit with such ID is not found")

      _ ->
        :ok
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end