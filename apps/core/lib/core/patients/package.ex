defmodule Core.Patients.Package do
  @moduledoc false

  alias Core.Condition
  alias Core.Conditions
  alias Core.Jobs.PackageSaveConditionsJob
  alias Core.Jobs.PackageSaveObservationsJob
  alias Core.Jobs.PackageSavePatientJob
  alias Core.Mongo
  alias Core.Observation
  alias Core.Observations

  @collection "patients"
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def consume_save_patient(
        %PackageSavePatientJob{patient_id: patient_id, patient_id_hash: patient_id_hash, encounter: encounter} = job
      ) do
    {:ok, %{matched_count: 1, modified_count: 1}} =
      Mongo.update_one(@collection, %{"_id" => patient_id_hash}, job.patient_save_data)

    links =
      job.links ++
        [
          %{
            "entity" => "encounter",
            "href" => "/api/patients/#{patient_id}/encounters/#{encounter.id}"
          }
        ]

    event = %PackageSaveConditionsJob{
      _id: job._id,
      patient_id: patient_id,
      patient_id_hash: patient_id_hash,
      links: links,
      encounter: encounter,
      conditions: job.conditions,
      observations: job.observations
    }

    with :ok <- @kafka_producer.publish_encounter_package_event(event) do
      :ok
    end
  end

  def consume_save_conditions(
        %PackageSavePatientJob{patient_id: patient_id, patient_id_hash: patient_id_hash, encounter: encounter} = job
      ) do
    links = insert_conditions(job.links, job.conditions, patient_id)

    event = %PackageSaveObservationsJob{
      _id: job._id,
      patient_id: patient_id,
      patient_id_hash: patient_id_hash,
      links: links,
      encounter: encounter,
      observations: job.observations
    }

    with :ok <- @kafka_producer.publish_encounter_package_event(event) do
      :ok
    end
  end

  def consume_save_observations(%PackageSaveObservationsJob{patient_id: patient_id} = job) do
    links = insert_observations(job.links, job.observations, patient_id)
    {:ok, %{"links" => links}, 200}
  end

  defp insert_conditions(links, [], _), do: links

  defp insert_conditions(links, conditions, patient_id) do
    conditions = Enum.map(conditions, &Conditions.create/1)
    {:ok, %{inserted_ids: condition_ids}} = Mongo.insert_many(Condition.metadata().collection, conditions, [])

    Enum.reduce(condition_ids, links, fn {_, condition_id}, acc ->
      acc ++
        [
          %{
            "entity" => "condition",
            "href" => "/api/patients/#{patient_id}/conditions/#{condition_id}"
          }
        ]
    end)
  end

  defp insert_observations(links, [], _), do: links

  defp insert_observations(links, observations, patient_id) do
    observations = Enum.map(observations, &Observations.create/1)
    {:ok, %{inserted_ids: observation_ids}} = Mongo.insert_many(Observation.metadata().collection, observations, [])

    Enum.reduce(observation_ids, links, fn {_, observation_id}, acc ->
      acc ++
        [
          %{
            "entity" => "observation",
            "href" => "/api/patients/#{patient_id}/observations/#{observation_id}"
          }
        ]
    end)
  end
end
