defmodule Core.Validators.ObservationContext do
  @moduledoc false

  alias Core.Mongo
  alias Core.Observation
  import Core.ValidationError

  @status_entered_in_error Observation.status(:entered_in_error)

  def validate(value, options) do
    observations = Keyword.get(options, :observations) || []
    observation_ids = Enum.map(observations, &Map.get(&1, :_id))
    patient_id_hash = Keyword.get(options, :patient_id_hash)

    if value in observation_ids do
      :ok
    else
      case Mongo.find_one(Observation.collection(), %{
             "_id" => Mongo.string_to_uuid(value),
             "patient_id" => patient_id_hash
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
end
