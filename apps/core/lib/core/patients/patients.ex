defmodule Core.Patients do
  @moduledoc false

  alias Core.AllergyIntolerance
  alias Core.Condition
  alias Core.Encounter
  alias Core.Episode
  alias Core.Immunization
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.VisitCreateJob
  alias Core.Mongo
  alias Core.Observation
  alias Core.Patient
  alias Core.Patients.Validators
  alias Core.Period
  alias Core.Reference
  alias Core.Validators.JsonSchema
  alias Core.Validators.Signature
  alias Core.Validators.Vex
  alias Core.Visit
  alias EView.Views.ValidationError
  import Core.Schema, only: [add_validations: 3]

  @collection Patient.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def get_by_id(id) do
    Mongo.find_one(@collection, %{"_id" => id})
  end

  def produce_create_episode(%{"patient_id" => patient_id} = params, user_id, client_id) do
    with %{} = patient <- get_by_id(patient_id),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:episode_create, Map.delete(params, "patient_id")),
         {:ok, job, episode_create_job} <-
           Jobs.create(EpisodeCreateJob, params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)),
         :ok <- @kafka_producer.publish_medical_event(episode_create_job) do
      {:ok, job}
    end
  end

  def produce_create_visit(%{"patient_id" => patient_id} = params, user_id, client_id) do
    with %{} = patient <- get_by_id(patient_id),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:visit_create, Map.delete(params, "patient_id")),
         {:ok, job, visit_create_job} <-
           Jobs.create(VisitCreateJob, params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)),
         :ok <- @kafka_producer.publish_medical_event(visit_create_job) do
      {:ok, job}
    end
  end

  def consume_create_visit(%VisitCreateJob{_id: id, patient_id: patient_id, user_id: user_id} = job) do
    now = DateTime.utc_now()

    with {:ok, %{"data" => data}} <- @digital_signature.decode(job.signed_data, []),
         {:ok, %{"content" => content, "signer" => signer}} <- Signature.validate(data),
         :ok <- JsonSchema.validate(:visit_create_signed_content, content) do
      with {:ok, visit} <- create_visit(job),
           {:ok, encounter} <- create_encounter(job, content) do
        {:ok, ""}
      end
    else
      {:error, error} ->
        {:ok, Jason.encode!(ValidationError.render("422.json", %{schema: error}))}
    end
  end

  def consume_create_episode(%EpisodeCreateJob{_id: id, patient_id: patient_id, client_id: client_id} = job) do
    now = DateTime.utc_now()

    # add period validations
    period =
      job.period
      |> Period.create()
      |> add_validations(
        :start,
        datetime: [less_than_or_equal_to: now, message: "Start date of episode must be in past"]
      )
      |> add_validations(:end, absence: [message: "End date of episode could not be submitted on creation"])

    # add managing_organization validations
    managing_organization =
      job.managing_organization
      |> Reference.create()
      |> add_validations(:identifier, reference: [path: "identifier"])

    identifier =
      managing_organization.identifier
      |> add_validations(:type, reference: [path: "type"])
      |> add_validations(
        :value,
        value: [equals: client_id, message: "User can create an episode only for the legal entity for which he works"]
      )

    codeable_concept = add_validations(identifier.type, :coding, reference: [path: "coding"])

    coding =
      Enum.map(
        codeable_concept.coding,
        &(&1
          |> add_validations(
            :code,
            value: [equals: "legal_entity", message: "Only legal_entity could be submitted as a managing_organization"]
          )
          |> add_validations(
            :system,
            value: [equals: "eHealth/resources", message: "Submitted system is not allowed for this field"]
          ))
      )

    managing_organization = %{
      managing_organization
      | identifier: %{identifier | type: %{codeable_concept | coding: coding}}
    }

    # add care_manager organizations
    care_manager =
      job.care_manager
      |> Reference.create()
      |> add_validations(:identifier, reference: [path: "identifier"])

    identifier =
      care_manager.identifier
      |> add_validations(:type, reference: [path: "type"])
      |> add_validations(
        :value,
        employee: [
          type: "DOCTOR",
          status: "active",
          legal_entity_id: client_id,
          messages: [
            type: "Employee submitted as a care_manager is not a doctor",
            status: "Doctor submitted as a care_manager is not active",
            legal_entity_id: "User can create an episode only for the doctor that works for the same legal_entity"
          ]
        ]
      )

    codeable_concept = add_validations(identifier.type, :coding, reference: [path: "coding"])

    coding =
      Enum.map(
        codeable_concept.coding,
        &(&1
          |> add_validations(
            :code,
            value: [equals: "employee", message: "Only employee could be submitted as a care_manager"]
          )
          |> add_validations(
            :system,
            value: [equals: "eHealth/resources", message: "Submitted system is not allowed for this field"]
          ))
      )

    care_manager = %{
      care_manager
      | identifier: %{identifier | type: %{codeable_concept | coding: coding}}
    }

    episode = %Episode{
      id: job.id,
      name: job.name,
      type: job.type,
      status: job.status,
      managing_organization: managing_organization,
      period: period,
      care_manager: care_manager,
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
            {:ok,
             %{
               "links" => [
                 %{"entity" => "episode", "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"}
               ]
             }}

          _ ->
            {:ok, %{"error" => "Episode with such id already exists"}}
        end

      errors ->
        {:ok, ValidationError.render("422.json", %{schema: Enum.map(errors, &Mongo.vex_to_json/1)})}
    end
  end

  defp create_visit(%VisitCreateJob{visit: nil}), do: {:ok, nil}

  defp create_visit(%VisitCreateJob{patient_id: patient_id, user_id: user_id, visit: visit}) do
    visit = Visit.create(visit)
    now = DateTime.utc_now()

    period =
      visit.period
      |> add_validations(
        :start,
        datetime: [less_than_or_equal_to: now, message: "Start date must be in past"]
      )
      |> add_validations(
        :end,
        presence: true,
        datetime: [less_than_or_equal_to: now, message: "Start date must be in past"],
        datetime: [greater_than: visit.period.start, message: "End date must be greater than the start date"]
      )

    visit = %{
      visit
      | period: period,
        inserted_by: user_id,
        updated_by: user_id,
        inserted_at: now,
        updated_at: now
    }

    case Vex.errors(visit) do
      [] ->
        case Mongo.find_one(
               Patient.metadata().collection,
               %{"_id" => patient_id},
               projection: ["visits.#{visit.id}": true]
             ) do
          %{"visits" => visits} when visits == %{} ->
            {:ok, visit}

          _ ->
            {:error, "Visit with such id already exists"}
        end

      errors ->
        {:error, errors}
    end
  end

  defp create_encounter(%VisitCreateJob{patient_id: patient_id, user_id: user_id}, content) do
    now = DateTime.utc_now()
    encounter = Encounter.create(content["encounter"])

    encounter = %{encounter | inserted_by: user_id, updated_by: user_id, inserted_at: now, updated_at: now}

    # TODO: not completed encounter validations
    encounter =
      encounter
      |> add_validations(:contexts, length: [min: 2, max: 2])

    case Vex.errors(encounter) do
      [] ->
        episode_context =
          Enum.find(encounter.contexts, fn context ->
            context.identifier.type.coding |> hd |> Map.get(:code) == "episode"
          end)

        episode_id = episode_context.identifier.value

        encounter_search =
          Patient.metadata().collection
          |> Mongo.aggregate([
            %{"$match" => %{"_id" => "9faade0a-827a-409d-b90d-4dcec13cecdb"}},
            %{
              "$project" => %{
                "_id" => "$_id",
                "encounter" => "$episodes.#{episode_id}.encounters.#{encounter.id}"
              }
            }
          ])
          |> Enum.to_list()

        case encounter_search do
          %{"encounter" => _} ->
            {:error, "Encounter with such id already exists"}

          _ ->
            {:ok, encounter}
        end

      errors ->
        {:error, errors}
    end
  end
end
