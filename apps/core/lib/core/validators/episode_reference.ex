defmodule Core.Validators.EpisodeReference do
  @moduledoc false

  use Vex.Validator
  alias Core.Mongo
  alias Core.Patient

  def validate(episode_id, options) do
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

    with :ok <- validate_field(:id, result, episode_id, options),
         :ok <- validate_field(:status, result, episode_id, options),
         :ok <- validate_field(:managing_organization, result, episode_id, options) do
      :ok
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end

  defp validate_field(:id, search_result, episode_id, options) do
    episode_id = Mongo.string_to_uuid(episode_id)

    case search_result do
      [%{"_id" => ^episode_id}] -> :ok
      _ -> error(options, "Episode with such ID is not found")
    end
  end

  defp validate_field(:status, search_result, _, options) do
    if Keyword.has_key?(options, :status) do
      status = Keyword.get(options, :status)

      case search_result do
        [%{"status" => ^status}] -> :ok
        _ -> error(options, "Episode is not #{status}")
      end
    else
      :ok
    end
  end

  defp validate_field(:managing_organization, search_result, _, options) do
    if Keyword.has_key?(options, :client_id) do
      client_id = options |> Keyword.get(:client_id) |> Mongo.string_to_uuid()

      case search_result do
        [%{"managing_organization" => ^client_id}] -> :ok
        _ -> error(options, "Managing_organization does not correspond to user's legal_entity")
      end
    else
      :ok
    end
  end
end
