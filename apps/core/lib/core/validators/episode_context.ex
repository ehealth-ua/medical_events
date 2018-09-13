defmodule Core.Validators.EpisodeContext do
  @moduledoc false

  use Vex.Validator
  alias Core.Episode
  alias Core.Mongo
  alias Core.Patient

  @status_active Episode.status(:active)

  def validate(episode_id, options) do
    patient_id = Keyword.get(options, :patient_id)

    result =
      Patient.metadata().collection
      |> Mongo.aggregate([
        %{"$match" => %{"_id" => patient_id}},
        %{"$project" => %{"_id" => "$episodes.#{episode_id}.id", "status" => "$episodes.#{episode_id}.status"}}
      ])
      |> Enum.to_list()

    case result do
      [%{"_id" => ^episode_id, "status" => @status_active}] ->
        :ok

      [%{"_id" => ^episode_id}] ->
        error(options, "Episode is not active")

      _ ->
        error(options, "Episode with such ID is not found")
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
