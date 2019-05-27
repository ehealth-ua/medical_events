defmodule Core.Validators.ObservationReference do
  @moduledoc false

  alias Core.Mongo
  alias Core.Observation

  @status_entered_in_error Observation.status(:entered_in_error)

  def validate(value, options) do
    patient_id_hash = Keyword.get(options, :patient_id_hash)

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

  def error(options, default_message) do
    {:error, Keyword.get(options, :message, default_message)}
  end
end
