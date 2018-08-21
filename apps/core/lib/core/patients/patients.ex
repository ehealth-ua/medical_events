defmodule Core.Patients do
  @moduledoc false

  alias Core.Episode
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.VisitCreateJob
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients.Validators
  alias Core.Validators.JsonSchema
  alias Core.Validators.Signature
  alias EView.Views.ValidationError
  import Core.Condition
  import Core.Encounter
  import Core.Immunization
  import Core.Observation
  import Core.Visit

  @collection Patient.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def get_by_id(id) do
    Mongo.find_one(@collection, %{"_id" => id})
  end

  def produce_create_episode(%{"patient_id" => patient_id} = params, user_id) do
    with %{} = patient <- get_by_id(patient_id),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:episode_create, Map.delete(params, "patient_id")),
         {:ok, job, episode_create_job} <- Jobs.create(EpisodeCreateJob, Map.put(params, "user_id", user_id)),
         :ok <- @kafka_producer.publish_medical_event(episode_create_job) do
      {:ok, job}
    end
  end

  def produce_create_visit(%{"patient_id" => patient_id} = params) do
    with %{} = patient <- get_by_id(patient_id),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:visit_create, Map.delete(params, "patient_id")),
         {:ok, job, visit_create_job} <- Jobs.create(VisitCreateJob, params),
         :ok <- @kafka_producer.publish_medical_event(visit_create_job) do
      {:ok, job}
    end
  end

  def consume_create_visit(%VisitCreateJob{_id: id, visits: visits} = job) do
    visits = Enum.into(visits || [], %{}, &{Map.get(&1, "id"), create_visit(&1)})

    case collect_signed_data(job) do
      {:error, error} ->
        Jobs.update(id, Job.status(:processed), error)
        :ok

      %{
        "encounters" => encounters,
        "conditions" => conditions,
        "observations" => observations,
        # "allergy_intolerances" => allergy_intolerances,
        "immunizations" => immunizations
      } ->
        set =
          %{}
          |> add_to_set(visits, "visits")
          # |> add_to_set(allergy_intolerances, "allergy_intolerances")
          |> add_to_set(immunizations, "immunizations")

        Mongo.update_one(@collection, %{"id" => id}, %{"$set" => set})
    end
  end

  def consume_create_episode(%EpisodeCreateJob{_id: id, patient_id: patient_id} = job) do
    now = DateTime.utc_now()

    episode = %Episode{
      id: job.id,
      name: job.name,
      type: job.type,
      status: job.status,
      managing_organization: job.managing_organization,
      period: job.period,
      care_manager: job.care_manager,
      inserted_by: job.user_id,
      updated_by: job.user_id,
      inserted_at: now,
      updated_at: now
    }

    case Vex.errors(episode) do
      [] ->
        case Mongo.find_one(
               Patient.metadata().collection,
               %{"_id" => patient_id},
               projection: ["episodes.#{episode.id}": true]
             ) do
          %{"episodes" => episodes} when episodes == %{} ->
            set = Mongo.add_to_set(%{"updated_by" => episode.updated_by}, episode, "episodes.#{episode.id}")

            {:ok, %{matched_count: 1, modified_count: 1}} =
              Mongo.update_one(@collection, %{"_id" => patient_id}, %{"$set" => set})

            # TODO: define success response
            {:ok, %{}}

          _ ->
            {:ok, %{"error" => "Episode with id #{episode.id} already exists"}}
        end

      errors ->
        {:ok, ValidationError.render("422.json", %{schema: Enum.map(errors, &Mongo.vex_to_json/1)})}
    end
  end

  defp add_to_set(set, values, path) do
    Enum.reduce(values, set, fn value, acc ->
      value_updates =
        Enum.reduce(value, %{}, fn {k, v}, value_acc ->
          Map.put(value_acc, "#{path}.#{value["id"]}.#{k}", v)
        end)

      Map.merge(acc, value_updates)
    end)
  end

  defp collect_signed_data(%VisitCreateJob{signed_data: signed_data}) do
    initial_data = %{
      "encounters" => %{},
      "conditions" => %{},
      "observations" => %{},
      # "allergy_intolerances" => %{},
      "immunizations" => %{}
    }

    signed_data
    |> Enum.with_index()
    |> Enum.reduce_while(initial_data, fn {signed_content, index}, acc ->
      with {:ok, %{"data" => data}} <- @digital_signature.decode(signed_content, []),
           {:ok, %{"content" => content, "signer" => signer}} <- Signature.validate(data),
           :ok <- JsonSchema.validate(:visit_create_signed_content, content) do
        encounters = Enum.into(Map.get(content, "encounters", []), %{}, &{Map.get(&1, "id"), create_encounter(&1)})
        conditions = Enum.into(Map.get(content, "conditions", []), %{}, &{Map.get(&1, "id"), create_condition(&1)})

        observations =
          Enum.into(Map.get(content, "observations", []), %{}, &{Map.get(&1, "id"), create_observation(&1)})

        # allergy_intolerances =
        #   Enum.into(
        #     Map.get(content, "allergy_intolerances"),
        #     %{},
        #     &{Map.get(&1, "id"), create_allergy_intolerance(&1)}
        #   )

        immunizations =
          Enum.into(Map.get(content, "immunizations", []), %{}, &{Map.get(&1, "id"), create_immunization(&1)})

        {:cont,
         %{
           acc
           | "encounters" => Map.merge(acc["encounters"], encounters),
             "conditions" => Map.merge(acc["conditions"], conditions),
             "observations" => Map.merge(acc["observations"], observations),
             # "allergy_intolerances" => Map.merge(acc["allergy_intolerances"], allergy_intolerances),
             "immunizations" => Map.merge(acc["immunizations"], immunizations)
         }}
      else
        {:error, error} ->
          {:halt, {:error, Jason.encode!(ValidationError.render("422.json", %{schema: error}))}}
      end
    end)
  end
end
