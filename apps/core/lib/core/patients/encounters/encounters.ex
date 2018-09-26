defmodule Core.Patients.Encounters do
  @moduledoc false

  alias Core.Encounter
  alias Core.Mongo
  alias Core.Patient

  require Logger

  @patient_collection Patient.metadata().collection

  def get_episode_encounters(
        patient_id,
        %BSON.Binary{} = episode_id,
        project \\ %{
          "episode_id" => "$encounters.v.episode.identifier.value",
          "encounter_id" => "$encounters.v.id"
        }
      ) do
    pipeline = [
      %{
        "$match" => %{
          "_id" => patient_id
        }
      },
      %{"$project" => %{"encounters" => %{"$objectToArray" => "$encounters"}}},
      %{"$unwind" => "$encounters"},
      %{
        "$match" => %{
          "encounters.v.episode.identifier.value" => episode_id
        }
      },
      %{
        "$project" => project
      }
    ]

    @patient_collection
    |> Mongo.aggregate(pipeline)
    |> Enum.to_list()
  end

  def fill_up_encounter_performer(%Encounter{performer: performer} = encounter) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{performer.identifier.value}") do
      first_name = get_in(employee, ["party", "first_name"])
      second_name = get_in(employee, ["party", "second_name"])
      last_name = get_in(employee, ["party", "last_name"])

      %{encounter | performer: %{performer | display_value: "#{first_name} #{second_name} #{last_name}"}}
    else
      _ ->
        Logger.warn("Failed to fill up employee value for encounter")
        encounter
    end
  end
end
