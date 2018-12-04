defmodule Core.Validators.EpisodeContext do
  @moduledoc false

  use Vex.Validator
  alias Core.Episode
  alias Core.Mongo
  alias Core.Patient

  @status_active Episode.status(:active)

  def validate(episode_id, options) do
    client_id = Keyword.get(options, :client_id)
    patient_id_hash = Keyword.get(options, :patient_id_hash)

    result =
      Patient.metadata().collection
      |> Mongo.aggregate([
        %{"$match" => %{"_id" => patient_id_hash}},
        %{
          "$project" => %{
            "_id" => "$episodes.#{episode_id}.id",
            "status" => "$episodes.#{episode_id}.status",
            "managing_organization" => "$episodes.#{episode_id}.managing_organization.identifier.value"
          }
        }
      ])
      |> Enum.to_list()

    episode_mongo_id = Mongo.string_to_uuid(episode_id)
    client_mongo_id = Mongo.string_to_uuid(client_id)

    case result do
      [%{"_id" => ^episode_mongo_id, "status" => @status_active, "managing_organization" => ^client_mongo_id}] ->
        :ok

      [%{"_id" => ^episode_mongo_id, "status" => @status_active}] ->
        error(options, "Managing_organization does not correspond to user's legal_entity")

      [%{"_id" => ^episode_mongo_id}] ->
        error(options, "Episode is not active")

      _ ->
        error(options, "Episode with such ID is not found")
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
