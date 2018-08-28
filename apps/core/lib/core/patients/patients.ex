defmodule Core.Patients do
  @moduledoc false

  alias Core.Encounter
  alias Core.Episode
  alias Core.Jobs
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.PackageCreateJob
  alias Core.Mongo
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

  def produce_create_package(%{"patient_id" => patient_id} = params, user_id, client_id) do
    with %{} = patient <- get_by_id(patient_id),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:package_create, Map.delete(params, "patient_id")),
         {:ok, job, package_create_job} <-
           Jobs.create(PackageCreateJob, params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)),
         :ok <- @kafka_producer.publish_medical_event(package_create_job) do
      {:ok, job}
    end
  end

  def consume_create_package(%PackageCreateJob{patient_id: patient_id, user_id: user_id} = job) do
    now = DateTime.utc_now()

    with {:ok, %{"data" => data}} <- @digital_signature.decode(job.signed_data, []),
         {:ok, %{"content" => content, "signer" => _signer}} <- Signature.validate(data),
         :ok <- JsonSchema.validate(:package_create_signed_content, content) do
      with {:ok, visit} <- create_visit(job),
           {:ok, encounter} <- create_encounter(job, content, visit) do
        visit_id = if is_map(visit), do: visit.id

        set =
          %{"updated_by" => user_id, "updated_at" => now}
          |> Mongo.add_to_set(visit, "visits.#{visit_id}")
          |> Mongo.add_to_set(encounter, "encounters.#{encounter.id}")

        {:ok, %{matched_count: 1, modified_count: 1}} =
          Mongo.update_one(@collection, %{"_id" => patient_id}, %{"$set" => set})

        {:ok,
         %{
           "links" => [
             %{"entity" => "encounter", "href" => "/api/patients/#{patient_id}/encounters/#{encounter.id}"}
           ]
         }}
      end
    else
      {:error, error} ->
        {:ok, Jason.encode!(ValidationError.render("422.json", %{schema: error}))}
    end
  end

  def consume_create_episode(%EpisodeCreateJob{patient_id: patient_id, client_id: client_id} = job) do
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
    managing_organization = Reference.create(job.managing_organization)

    identifier =
      managing_organization.identifier
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

    identifier =
      care_manager.identifier
      |> add_validations(
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
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

    episode_id = episode.id

    case Vex.errors(episode) do
      [] ->
        case Mongo.find_one(
               Patient.metadata().collection,
               %{"_id" => patient_id},
               projection: ["episodes.#{episode_id}": true]
             ) do
          %{"episodes" => %{^episode_id => %{}}} ->
            {:ok, %{"error" => "Episode with such id already exists"}}

          _ ->
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
        end

      errors ->
        {:ok, ValidationError.render("422.json", %{schema: Enum.map(errors, &Mongo.vex_to_json/1)})}
    end
  end

  defp create_visit(%PackageCreateJob{visit: nil}), do: {:ok, nil}

  defp create_visit(%PackageCreateJob{patient_id: patient_id, user_id: user_id, visit: visit}) do
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
        datetime: [less_than_or_equal_to: now, message: "End date must be in past"],
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

    visit_id = visit.id

    case Vex.errors(visit) do
      [] ->
        case Mongo.find_one(
               Patient.metadata().collection,
               %{"_id" => patient_id},
               projection: ["visits.#{visit.id}": true]
             ) do
          %{"visits" => %{^visit_id => %{}}} ->
            {:error, "Visit with such id already exists"}

          _ ->
            {:ok, visit}
        end

      errors ->
        {:error, errors}
    end
  end

  defp create_encounter(
         %PackageCreateJob{patient_id: patient_id, user_id: user_id, client_id: client_id},
         content,
         visit
       ) do
    now = DateTime.utc_now()
    encounter = Encounter.create(content["encounter"])
    encounter = %{encounter | inserted_by: user_id, updated_by: user_id, inserted_at: now, updated_at: now}

    encounter =
      encounter
      |> add_validations(
        :contexts,
        reference_type: [type: "visit", message: "Contexts does not contain reference to the Visit"],
        reference_type: [type: "episode", message: "Contexts does not contain reference to the Episode"]
      )

    # Contexts validations
    contexts =
      Enum.map(encounter.contexts, fn context ->
        identifier = context.identifier
        codeable_concept = add_validations(identifier.type, :coding, length: [min: 1, max: 1])
        identifier = %{identifier | type: codeable_concept}

        coding_code =
          codeable_concept.coding
          |> List.first()
          |> Map.get(:code)

        identifier =
          case coding_code do
            "visit" ->
              add_validations(
                identifier,
                :value,
                visit_context: [visit: visit, patient_id: patient_id]
              )

            "episode" ->
              add_validations(
                identifier,
                :value,
                episode_context: [patient_id: patient_id]
              )

            _ ->
              identifier
          end

        %{context | identifier: identifier}
      end)

    # Performer validations
    performer = encounter.performer

    identifier =
      performer.identifier
      |> add_validations(
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee submitted as a care_manager is not a doctor",
            status: "Doctor submitted as a care_manager is not active",
            legal_entity_id: "User can create an episode only for the doctor that works for the same legal_entity"
          ]
        ]
      )

    performer = %{performer | identifier: identifier}

    # Division validations
    division = encounter.division

    identifier =
      division.identifier
      |> add_validations(
        :value,
        division: [
          status: "active",
          legal_entity_id: client_id,
          messages: [
            status: "Division is not active",
            legal_entity_id: "User is not allowed to create encouners for this division"
          ]
        ]
      )

    division = %{division | identifier: identifier}

    encounter =
      %{encounter | contexts: contexts, performer: performer, division: division}
      |> add_validations(
        :diagnoses,
        diagnoses_role: [type: "chief_complaint", message: "Encounter must have at least one chief complaint"]
      )

    case Vex.errors(encounter) do
      [] ->
        result =
          Patient.metadata().collection
          |> Mongo.aggregate([
            %{"$match" => %{"_id" => patient_id}},
            %{"$project" => %{"_id" => "$encounters.#{encounter.id}.id"}}
          ])
          |> Enum.to_list()

        case result do
          [%{"_id" => _}] ->
            {:error, "Encounter with such id already exists"}

          _ ->
            {:ok, encounter}
        end

      errors ->
        {:error, errors}
    end
  end
end
