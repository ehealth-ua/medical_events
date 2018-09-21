defmodule Core.Validators.ObservationReference do
  @moduledoc false

  use Vex.Validator
  alias Core.Mongo
  alias Core.Observation

  @status_entered_in_error Observation.status(:entered_in_error)

  def validate(value, options) do
    observations = Keyword.get(options, :observations)
    observation_ids = Enum.map(observations, &Map.get(&1, :_id))
    patient_id = Keyword.get(options, :patient_id)

    if value in observation_ids do
      :ok
    else
      case Mongo.find_one(Observation.metadata().collection, %{
             "_id" => Mongo.string_to_uuid(value),
             "patient_id" => patient_id
           }) do
        nil ->
          error(options, "Observation with such id is not found")

        %{"status" => @status_entered_in_error} ->
          error(options, ~s(Observation in "entered_in_error" status can not be referenced))

        _ ->
          :ok
      end
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
