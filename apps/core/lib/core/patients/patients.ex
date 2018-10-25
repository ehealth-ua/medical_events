defmodule Core.Patients do
  @moduledoc false

  use Confex, otp_app: :core

  alias Core.AllergyIntolerance
  alias Core.Condition
  alias Core.DatePeriod
  alias Core.DiagnosesHistory
  alias Core.Encounter
  alias Core.Episode
  alias Core.Immunization
  alias Core.Jobs
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Jobs.PackageCancelJob
  alias Core.Jobs.PackageCreateJob
  alias Core.Jobs.PackageSavePatientJob
  alias Core.Mongo
  alias Core.Observation
  alias Core.Patient
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Encounters
  alias Core.Patients.Episodes
  alias Core.Patients.Immunizations
  alias Core.Patients.Validators
  alias Core.StatusHistory
  alias Core.Validators.JsonSchema
  alias Core.Validators.Signature
  alias Core.Validators.Vex
  alias Core.Visit
  alias Core.Conditions.Validations, as: ConditionValidations
  alias Core.Observations.Validations, as: ObservationValidations
  alias Core.Patients.AllergyIntolerances.Validations, as: AllergyIntoleranceValidations
  alias Core.Patients.Episodes.Validations, as: EpisodeValidations
  alias Core.Patients.Encounters.Cancel, as: CancelEncounter
  alias Core.Patients.Encounters.Validations, as: EncounterValidations
  alias Core.Patients.Immunizations.Reaction
  alias Core.Patients.Immunizations.Validations, as: ImmunizationValidations
  alias Core.Patients.Visits.Validations, as: VisitValidations
  alias EView.Views.ValidationError

  require Logger

  @collection Patient.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @media_storage Application.get_env(:core, :microservices)[:media_storage]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def get_pk_hash(nil), do: nil

  def get_pk_hash(value) do
    :sha256
    |> :crypto.hash_init()
    |> :crypto.hash_update(value)
    |> :crypto.hash_update(config()[:pk_hash_salt])
    |> :crypto.hash_final()
    |> Base.encode16()
  end

  def get_by_id(id) do
    Mongo.find_one(@collection, %{"_id" => id})
  end

  def produce_create_episode(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:episode_create, Map.drop(params, ~w(patient_id patient_id_hash))),
         {:ok, job, episode_create_job} <-
           Jobs.create(
             EpisodeCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_create_job) do
      {:ok, job}
    end
  end

  def produce_update_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_update, request_params),
         {:ok, job, episode_update_job} <-
           Jobs.create(
             EpisodeUpdateJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_update_job) do
      {:ok, job}
    end
  end

  def produce_close_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_close, request_params),
         {:ok, job, episode_close_job} <-
           Jobs.create(
             EpisodeCloseJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_close_job) do
      {:ok, job}
    end
  end

  def produce_cancel_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_cancel, request_params),
         {:ok, job, episode_cancel_job} <-
           Jobs.create(
             EpisodeCancelJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_cancel_job) do
      {:ok, job}
    end
  end

  def produce_create_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:package_create, Map.take(params, ["signed_data", "visit"])),
         {:ok, job, package_create_job} <-
           Jobs.create(
             PackageCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(package_create_job) do
      {:ok, job}
    end
  end

  def produce_cancel_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with :ok <- JsonSchema.validate(:package_cancel, Map.take(params, ["signed_data"])),
         %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient) do
      job_data =
        params
        |> Map.put("user_id", user_id)
        |> Map.put("client_id", client_id)

      with {:ok, job, package_cancel_job} <- Jobs.create(PackageCancelJob, job_data),
           :ok <- @kafka_producer.publish_medical_event(package_cancel_job) do
        {:ok, job}
      end
    end
  end

  def consume_cancel_package(%PackageCancelJob{patient_id_hash: patient_id_hash, user_id: user_id} = job) do
    with {:ok, data} <- decode_signed_data(job.signed_data),
         {:ok, %{"content" => content, "signer" => signer}} <- validate_signed_data(data),
         :ok <- JsonSchema.validate(:package_cancel_signed_content, content),
         employee_id <- get_in(content, ["encounter", "performer", "identifier", "value"]),
         encounter_id <- content["encounter"]["id"],
         :ok <- validate_signatures(signer, employee_id, user_id, job.client_id),
         {_, %{} = patient} <- {:patient, get_by_id(patient_id_hash)},
         {_, {:ok, %Encounter{} = encounter}} <- {:encounter, Encounters.get_by_id(patient_id_hash, encounter_id)},
         {_, {:ok, %Episode{} = episode}} <-
           {:episode, Episodes.get(patient_id_hash, to_string(encounter.episode.identifier.value))},
         :ok <- CancelEncounter.validate(content, episode, encounter, patient_id_hash, job.client_id),
         :ok <- CancelEncounter.save(patient, content, episode, encounter_id, job) do
      :ok
    else
      {:patient, _} -> {:ok, %{"error" => "Patient not found"}, 404}
      {:episode, _} -> {:ok, %{"error" => "Encounter's episode not found"}, 404}
      {:encounter, _} -> {:ok, %{"error" => "Encounter not found"}, 404}
      {:error, error} -> {:ok, ValidationError.render("422.json", %{schema: error}), 422}
      error -> error
    end
  end

  def consume_create_package(
        %PackageCreateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          user_id: user_id
        } = job
      ) do
    now = DateTime.utc_now()

    with {:ok, data} <- decode_signed_data(job.signed_data),
         {:ok, %{"content" => content, "signer" => signer}} <- validate_signed_data(data),
         :ok <- JsonSchema.validate(:package_create_signed_content, content),
         employee_id <- get_in(content, ["encounter", "performer", "identifier", "value"]),
         :ok <- validate_signatures(signer, employee_id, user_id, job.client_id) do
      with {:ok, visit} <- create_visit(job),
           {:ok, observations} <- create_observations(job, content),
           {:ok, conditions} <- create_conditions(job, content, observations),
           {:ok, encounter} <- create_encounter(job, content, conditions, visit),
           {:ok, immunizations} <- create_immunizations(job, content, observations),
           {:ok, allergy_intolerances} <- create_allergy_intolerances(job, content) do
        visit_id = if is_map(visit), do: visit.id
        encounter = Encounters.fill_up_encounter_performer(encounter)
        resource_name = "#{encounter.id}/create"
        files = [{'signed_content.txt', job.signed_data}]
        {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

        with :ok <-
               @media_storage.save(
                 patient_id,
                 compressed_content,
                 Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:encounter_bucket],
                 resource_name
               ) do
          encounter = %{encounter | signed_content_links: [resource_name]}

          set =
            %{"updated_by" => user_id, "updated_at" => now}
            |> Mongo.add_to_set(visit, "visits.#{visit_id}")
            |> Mongo.add_to_set(encounter, "encounters.#{encounter.id}")
            |> Mongo.convert_to_uuid("visits.#{visit_id}.id")
            |> Mongo.convert_to_uuid("visits.#{visit_id}.inserted_by")
            |> Mongo.convert_to_uuid("visits.#{visit_id}.updated_by")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.id")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.inserted_by")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.updated_by")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.division.identifier.value")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.episode.identifier.value")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.performer.identifier.value")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.visit.identifier.value")
            |> Mongo.convert_to_uuid(
              "encounters.#{encounter.id}.diagnoses",
              ~w(condition identifier value)a
            )
            |> Mongo.convert_to_uuid(
              "encounters.#{encounter.id}.incoming_referrals",
              ~w(identifier value)a
            )
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.service_provider.identifier.value")
            |> Mongo.convert_to_uuid("updated_by")

          diagnoses_history =
            DiagnosesHistory.create(%{
              "date" => DateTime.utc_now(),
              "evidence" => %{
                "identifier" => %{
                  "type" => %{
                    "coding" => [
                      %{
                        "system" => "eHealth/resources",
                        "code" => "encounter"
                      }
                    ]
                  },
                  "value" => Mongo.string_to_uuid(encounter.id)
                }
              },
              "is_active" => true
            })

          diagnoses_history = %{
            diagnoses_history
            | diagnoses:
                Enum.map(encounter.diagnoses, fn diagnosis ->
                  condition = diagnosis.condition

                  %{
                    diagnosis
                    | condition: %{
                        condition
                        | identifier: %{
                            condition.identifier
                            | value: Mongo.string_to_uuid(condition.identifier.value)
                          }
                      }
                  }
                end)
          }

          set =
            Mongo.add_to_set(
              set,
              diagnoses_history.diagnoses,
              "episodes.#{encounter.episode.identifier.value}.current_diagnoses"
            )

          push =
            Mongo.add_to_push(
              %{},
              diagnoses_history,
              "episodes.#{encounter.episode.identifier.value}.diagnoses_history"
            )

          set = Enum.reduce(immunizations, set, &add_immunization_to_set/2)

          set =
            Enum.reduce(allergy_intolerances, set, fn allergy_intolerance, acc ->
              allergy_intolerance = AllergyIntolerances.fill_up_allergy_intolerance_asserter(allergy_intolerance)

              acc
              |> Mongo.add_to_set(
                allergy_intolerance,
                "allergy_intolerances.#{allergy_intolerance.id}"
              )
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.id")
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.inserted_by")
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.updated_by")
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.context.identifier.value")
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.source.value.identifier.value")
            end)

          links = []

          links =
            Enum.reduce(immunizations, links, fn immunization, acc ->
              acc ++
                [
                  %{
                    "entity" => "immunization",
                    "href" => "/api/patients/#{patient_id}/immunizations/#{immunization.id}"
                  }
                ]
            end)

          links =
            Enum.reduce(allergy_intolerances, links, fn allergy_intolerance, acc ->
              acc ++
                [
                  %{
                    "entity" => "allergy_intolerance",
                    "href" => "/api/patients/#{patient_id}/allergy_intolerances/#{allergy_intolerance.id}"
                  }
                ]
            end)

          event = %PackageSavePatientJob{
            _id: job._id,
            patient_id: patient_id,
            patient_id_hash: patient_id_hash,
            patient_save_data: %{
              "$set" => set,
              "$push" => push
            },
            links: links,
            encounter: encounter,
            conditions: conditions,
            observations: observations
          }

          with :ok <- @kafka_producer.publish_encounter_package_event(event) do
            :ok
          end
        else
          _ -> Logger.error("Failed to save signed content")
        end
      else
        {:error, error, status_code} ->
          {:ok, error, status_code}

        {:error, error} ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(error)}), 422}
      end
    else
      {:error, %{"error" => error, "meta" => _}} ->
        {:ok, Jason.encode!(error), 422}

      {:error, error} ->
        {:ok, ValidationError.render("422.json", %{schema: error}), 422}

      {:error, {:bad_request, error}} ->
        {:ok, error, 422}

      error ->
        error
    end
  end

  defp add_immunization_to_set(%{id: %BSON.Binary{}} = immunization, set) do
    set
    |> Mongo.add_to_set(immunization, "immunizations.#{immunization.id}")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.updated_by")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.reactions", ~w(detail identifier value)a)
  end

  defp add_immunization_to_set(immunization, set) do
    immunization = Immunizations.fill_up_immunization_performer(immunization)

    set
    |> Mongo.add_to_set(immunization, "immunizations.#{immunization.id}")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.id")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.inserted_by")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.updated_by")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.context.identifier.value")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.legal_entity.identifier.value")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.source.value.identifier.value")
    |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.reactions", ~w(detail identifier value)a)
  end

  def consume_create_episode(
        %EpisodeCreateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          client_id: client_id
        } = job
      ) do
    now = DateTime.utc_now()

    episode =
      job
      |> Map.from_struct()
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Episode.create()

    episode =
      %{
        episode
        | status_history: [],
          diagnoses_history: [],
          inserted_by: job.user_id,
          updated_by: job.user_id,
          inserted_at: now,
          updated_at: now
      }
      |> EpisodeValidations.validate_period()
      |> EpisodeValidations.validate_managing_organization(client_id)
      |> EpisodeValidations.validate_care_manager(client_id)

    episode_id = episode.id

    case Vex.errors(episode) do
      [] ->
        case Episodes.get(patient_id_hash, episode_id) do
          {:ok, _} ->
            {:ok, %{"error" => "Episode with such id already exists"}, 422}

          _ ->
            episode =
              episode
              |> Episodes.fill_up_episode_care_manager()
              |> Episodes.fill_up_episode_managing_organization()

            set =
              %{"updated_by" => episode.updated_by}
              |> Mongo.add_to_set(episode, "episodes.#{episode.id}")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.id")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.inserted_by")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.updated_by")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.care_manager.identifier.value")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.managing_organization.identifier.value")
              |> Mongo.convert_to_uuid("updated_by")

            {:ok, %{matched_count: 1, modified_count: 1}} =
              Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{"$set" => set})

            {:ok,
             %{
               "links" => [
                 %{
                   "entity" => "episode",
                   "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
                 }
               ]
             }, 200}
        end

      errors ->
        {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
    end
  end

  def consume_update_episode(
        %EpisodeUpdateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          id: id,
          client_id: client_id
        } = job
      ) do
    now = DateTime.utc_now()
    status = Episode.status(:active)

    with {:ok, %Episode{status: ^status} = episode} <- Episodes.get(patient_id_hash, id) do
      changes = Map.take(job.request_params, ~w(name managing_organization care_manager))

      episode =
        %{episode | updated_by: job.user_id, updated_at: now}
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
        |> EpisodeValidations.validate_managing_organization(
          job.request_params["managing_organization"],
          client_id
        )
        |> EpisodeValidations.validate_care_manager(job.request_params["care_manager"], client_id)

      case Vex.errors(episode) do
        [] ->
          episode =
            episode
            |> Episodes.fill_up_episode_care_manager()
            |> Episodes.fill_up_episode_managing_organization()

          set =
            %{"updated_by" => episode.updated_by, "updated_at" => now}
            |> Mongo.add_to_set(episode.care_manager, "episodes.#{episode.id}.care_manager")
            |> Mongo.add_to_set(episode.name, "episodes.#{episode.id}.name")
            |> Mongo.add_to_set(
              episode.managing_organization,
              "episodes.#{episode.id}.managing_organization"
            )
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.updated_by")
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.care_manager.identifier.value")
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.managing_organization.identifier.value")
            |> Mongo.convert_to_uuid("updated_by")

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{"$set" => set})

          {:ok,
           %{
             "links" => [
               %{
                 "entity" => "episode",
                 "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
               }
             ]
           }, 200}

        errors ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
      end
    else
      {:ok, %Episode{status: status}} -> {:ok, "Episode in status #{status} can not be updated", 422}
      nil -> {:error, "Failed to get episode", 404}
    end
  end

  def consume_close_episode(%EpisodeCloseJob{patient_id: patient_id, patient_id_hash: patient_id_hash, id: id} = job) do
    now = DateTime.utc_now()
    status = Episode.status(:active)

    with {:ok, %Episode{status: ^status} = episode} <- Episodes.get(patient_id_hash, id) do
      managing_organization = episode.managing_organization
      identifier = managing_organization.identifier

      new_period = DatePeriod.create(job.request_params["period"])
      changes = Map.take(job.request_params, ~w(closing_summary status_reason))

      episode =
        %{
          episode
          | status: Episode.status(:closed),
            updated_by: job.user_id,
            updated_at: now,
            period: %{episode.period | end: new_period.end},
            managing_organization: %{
              managing_organization
              | identifier: %{identifier | value: UUID.binary_to_string!(identifier.value.binary)}
            }
        }
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
        |> EpisodeValidations.validate_period()
        |> EpisodeValidations.validate_managing_organization(job.client_id)

      case Vex.errors(episode) do
        [] ->
          set =
            %{"updated_by" => episode.updated_by, "updated_at" => episode.updated_at}
            |> Mongo.add_to_set(episode.status, "episodes.#{episode.id}.status")
            |> Mongo.add_to_set(episode.status_reason, "episodes.#{episode.id}.status_reason")
            |> Mongo.add_to_set(episode.closing_summary, "episodes.#{episode.id}.closing_summary")
            |> Mongo.add_to_set(episode.period.end, "episodes.#{episode.id}.period.end")
            |> Mongo.convert_to_uuid("updated_by")

          status_history =
            StatusHistory.create(%{
              "status" => episode.status,
              "status_reason" => episode.status_reason,
              "inserted_at" => episode.updated_at,
              "inserted_by" => Mongo.string_to_uuid(episode.updated_by)
            })

          push = Mongo.add_to_push(%{}, status_history, "episodes.#{episode.id}.status_history")

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{
              "$set" => set,
              "$push" => push
            })

          {:ok,
           %{
             "links" => [
               %{
                 "entity" => "episode",
                 "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
               }
             ]
           }, 200}

        errors ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
      end
    else
      {:ok, %Episode{status: status}} -> {:ok, "Episode in status #{status} can not be closed", 422}
      nil -> {:error, "Failed to get episode", 404}
    end
  end

  def consume_cancel_episode(%EpisodeCancelJob{patient_id: patient_id, patient_id_hash: patient_id_hash, id: id} = job) do
    now = DateTime.utc_now()
    status = Episode.status(:active)

    with {:ok, %Episode{status: ^status} = episode} <- Episodes.get(patient_id_hash, id) do
      managing_organization = episode.managing_organization
      identifier = managing_organization.identifier

      changes = Map.take(job.request_params, ~w(explanatory_letter status_reason))

      episode =
        %{
          episode
          | status: Episode.status(:cancelled),
            updated_by: job.user_id,
            updated_at: now,
            managing_organization: %{
              managing_organization
              | identifier: %{identifier | value: UUID.binary_to_string!(identifier.value.binary)}
            }
        }
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
        |> EpisodeValidations.validate_managing_organization(job.client_id)

      case Vex.errors(episode) do
        [] ->
          all_encounters_canceled =
            patient_id_hash
            |> Encounters.get_episode_encounters(Mongo.string_to_uuid(id), %{
              "status" => "$encounters.v.status"
            })
            |> Enum.map(& &1["status"])
            |> Enum.all?(fn status -> status == Encounter.status(:entered_in_error) end)

          if all_encounters_canceled do
            set =
              %{"updated_by" => episode.updated_by, "updated_at" => episode.updated_at}
              |> Mongo.add_to_set(episode.status, "episodes.#{episode.id}.status")
              |> Mongo.add_to_set(
                episode.explanatory_letter,
                "episodes.#{episode.id}.explanatory_letter"
              )
              |> Mongo.add_to_set(
                episode.status_reason,
                "episodes.#{episode.id}.status_reason"
              )
              |> Mongo.convert_to_uuid("updated_by")

            status_history =
              StatusHistory.create(%{
                "status" => episode.status,
                "status_reason" => episode.status_reason,
                "inserted_at" => episode.updated_at,
                "inserted_by" => Mongo.string_to_uuid(episode.updated_by)
              })

            push = Mongo.add_to_push(%{}, status_history, "episodes.#{episode.id}.status_history")

            {:ok, %{matched_count: 1, modified_count: 1}} =
              Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{
                "$set" => set,
                "$push" => push
              })

            {:ok,
             %{
               "links" => [
                 %{
                   "entity" => "episode",
                   "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
                 }
               ]
             }, 200}
          else
            {:error, "Episode can not be canceled while it has not canceled encounters", 409}
          end

        errors ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
      end
    else
      {:ok, %Episode{status: status}} ->
        {:ok, "Episode in status #{status} can not be canceled", 422}

      nil ->
        {:error, "Failed to get episode", 404}
    end
  end

  defp create_visit(%PackageCreateJob{visit: nil}), do: {:ok, nil}

  defp create_visit(%PackageCreateJob{
         patient_id_hash: patient_id_hash,
         user_id: user_id,
         visit: visit
       }) do
    now = DateTime.utc_now()
    visit = Visit.create(visit)

    visit =
      %{visit | inserted_by: user_id, updated_by: user_id, inserted_at: now, updated_at: now}
      |> VisitValidations.validate_period()

    case Vex.errors(%{visit: visit}, visit: [reference: [path: "visit"]]) do
      [] ->
        result =
          Patient.metadata().collection
          |> Mongo.aggregate([
            %{"$match" => %{"_id" => patient_id_hash}},
            %{"$project" => %{"_id" => "$visits.#{visit.id}.id"}}
          ])
          |> Enum.to_list()

        case result do
          [%{"_id" => _}] ->
            {:error, "Visit with such id already exists", 409}

          _ ->
            {:ok, visit}
        end

      errors ->
        {:error, errors}
    end
  end

  defp create_encounter(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         content,
         conditions,
         visit
       ) do
    now = DateTime.utc_now()
    encounter = Encounter.create(content["encounter"])

    encounter =
      %{
        encounter
        | inserted_by: user_id,
          updated_by: user_id,
          inserted_at: now,
          updated_at: now
      }
      |> EncounterValidations.validate_episode(client_id, patient_id_hash)
      |> EncounterValidations.validate_visit(visit, patient_id_hash)
      |> EncounterValidations.validate_performer(client_id)
      |> EncounterValidations.validate_division(client_id)
      |> EncounterValidations.validate_diagnoses(conditions, patient_id_hash)
      |> EncounterValidations.validate_date()

    case Vex.errors(%{encounter: encounter}, encounter: [reference: [path: "encounter"]]) do
      [] ->
        result =
          Patient.metadata().collection
          |> Mongo.aggregate([
            %{"$match" => %{"_id" => patient_id_hash}},
            %{"$project" => %{"_id" => "$encounters.#{encounter.id}.id"}}
          ])
          |> Enum.to_list()

        case result do
          [%{"_id" => _}] ->
            {:error, "Encounter with such id already exists", 409}

          _ ->
            {:ok, encounter}
        end

      errors ->
        {:error, errors}
    end
  end

  defp create_conditions(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"conditions" => _} = content,
         observations
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    conditions =
      Enum.map(content["conditions"], fn data ->
        condition = Condition.create(data)

        %{
          condition
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id,
            patient_id: patient_id_hash
        }
        |> ConditionValidations.validate_onset_date()
        |> ConditionValidations.validate_context(encounter_id)
        |> ConditionValidations.validate_evidences(observations, patient_id_hash)
        |> ConditionValidations.validate_source(client_id)
      end)

    case Vex.errors(
           %{conditions: conditions},
           conditions: [unique_ids: [field: :_id], reference: [path: "conditions"]]
         ) do
      [] ->
        validate_conditions(conditions)

      errors ->
        {:error, errors}
    end
  end

  defp create_conditions(_, _, _), do: {:ok, []}

  defp create_observations(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"observations" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    observations =
      Enum.map(content["observations"], fn data ->
        observation =
          data
          |> Map.drop(["reaction_on"])
          |> Observation.create()

        %{
          observation
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id,
            patient_id: patient_id_hash
        }
        |> ObservationValidations.validate_issued()
        |> ObservationValidations.validate_effective_at()
        |> ObservationValidations.validate_context(encounter_id)
        |> ObservationValidations.validate_source(client_id)
        |> ObservationValidations.validate_value()
        |> ObservationValidations.validate_components()
      end)

    case Vex.errors(
           %{observations: observations},
           observations: [unique_ids: [field: :_id], reference: [path: "observations"]]
         ) do
      [] ->
        validate_observations(observations)

      errors ->
        {:error, errors}
    end
  end

  defp create_observations(_, _), do: {:ok, []}

  defp create_immunizations(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         content,
         observations
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]
    immunization_observation_id_map = get_immunization_observation_id_map(content)
    db_immunization_ids = get_db_immunization_ids(content)

    immunizations =
      Enum.map(content["immunizations"] || [], fn data ->
        immunization =
          data
          |> create_immunization_reactions(immunization_observation_id_map)
          |> Immunization.create()

        %{
          immunization
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> ImmunizationValidations.validate_date()
        |> ImmunizationValidations.validate_context(encounter_id)
        |> ImmunizationValidations.validate_source(client_id)
        |> ImmunizationValidations.validate_reactions(observations, patient_id_hash)
      end)

    with {:ok, db_immunizations} <- get_db_immunizations(db_immunization_ids, patient_id_hash) do
      immunizations =
        immunizations ++ update_db_immunizations(db_immunizations, user_id, immunization_observation_id_map)

      case Vex.errors(
             %{immunizations: immunizations},
             immunizations: [unique_ids: [field: :id], reference: [path: "immunizations"]]
           ) do
        [] ->
          validate_immunizations(patient_id_hash, immunizations)

        errors ->
          {:error, errors}
      end
    end
  end

  defp get_db_immunizations(immunization_ids, patient_id_hash) do
    with {:ok, immunizations} <- Immunizations.get_by_ids(patient_id_hash, immunization_ids) do
      {:ok, immunizations}
    else
      {:error, message} -> {:error, %{"error" => message}, 404}
    end
  end

  defp update_db_immunizations(immunizations, user_id, immunization_observation_id_map) do
    now = DateTime.utc_now()

    Enum.map(immunizations, fn %{id: immunization_id} = immunization ->
      previous_reactions = immunization.reactions || []

      new_reactions =
        immunization_observation_id_map
        |> Map.get(to_string(immunization_id), [])
        |> Enum.map(&Reaction.create(create_reaction(&1)))

      reactions =
        previous_reactions
        |> Enum.concat(new_reactions)
        |> case do
          [] -> nil
          reactions -> reactions
        end

      %{immunization | reactions: reactions, updated_at: now, updated_by: user_id}
    end)
  end

  defp get_immunization_observation_id_map(content) do
    content
    |> Map.get("observations", [])
    |> Enum.reduce(%{}, fn %{"id" => observation_id} = observation, acc ->
      case get_reaction_on_immunization_id(observation["reaction_on"]) do
        nil -> acc
        immunization_id -> Map.merge(acc, %{immunization_id => [observation_id]}, fn _key, v1, v2 -> [v2 | v1] end)
      end
    end)
  end

  defp get_request_immunization_ids(content) do
    content
    |> Map.get("immunizations", [])
    |> Enum.map(& &1["id"])
  end

  defp get_reactions_immunization_ids(content) do
    content
    |> Map.get("observations", [])
    |> Enum.map(&get_reaction_on_immunization_id(&1["reaction_on"]))
    |> Enum.reject(&is_nil/1)
  end

  defp get_db_immunization_ids(content) do
    immunization_ids_from_request = get_request_immunization_ids(content)
    immunization_ids_from_reactions_on = get_reactions_immunization_ids(content)

    immunization_ids_from_reactions_on -- immunization_ids_from_request
  end

  defp get_reaction_on_immunization_id(%{"identifier" => %{"value" => immunization_id}}), do: immunization_id
  defp get_reaction_on_immunization_id(_), do: nil

  defp create_immunization_reactions(%{"id" => immunization_id} = data, immunization_observation_id_map) do
    case immunization_observation_id_map[immunization_id] do
      nil -> data
      observation_ids -> Map.put(data, "reactions", Enum.map(observation_ids, &create_reaction(&1)))
    end
  end

  defp create_reaction(observation_id) do
    %{
      "detail" => %{
        "identifier" => %{
          "type" => %{
            "coding" => [
              %{
                "system" => "eHealth/resources",
                "code" => "observation"
              }
            ]
          },
          "value" => observation_id
        }
      }
    }
  end

  defp create_allergy_intolerances(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"allergy_intolerances" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    allergy_intolerances =
      Enum.map(content["allergy_intolerances"], fn data ->
        allergy_intolerance = AllergyIntolerance.create(data)

        %{
          allergy_intolerance
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> AllergyIntoleranceValidations.validate_context(encounter_id)
        |> AllergyIntoleranceValidations.validate_source(client_id)
        |> AllergyIntoleranceValidations.validate_onset_date_time()
        |> AllergyIntoleranceValidations.validate_last_occurence()
        |> AllergyIntoleranceValidations.validate_asserted_date()
      end)

    case Vex.errors(
           %{allergy_intolerances: allergy_intolerances},
           allergy_intolerances: [
             unique_ids: [field: :id],
             reference: [path: "allergy_intolerances"]
           ]
         ) do
      [] ->
        validate_allergy_intolerances(patient_id_hash, allergy_intolerances)

      errors ->
        {:error, errors}
    end
  end

  defp create_allergy_intolerances(_, _), do: {:ok, []}

  defp validate_conditions(conditions) do
    Enum.reduce_while(conditions, {:ok, conditions}, fn condition, acc ->
      if Mongo.find_one(Condition.metadata().collection, %{"_id" => condition._id}, projection: %{"_id" => true}) do
        {:halt, {:error, "Condition with id '#{condition._id}' already exists", 409}}
      else
        {:cont, acc}
      end
    end)
  end

  defp validate_observations(observations) do
    Enum.reduce_while(observations, {:ok, observations}, fn observation, acc ->
      if Mongo.find_one(
           Observation.metadata().collection,
           %{"_id" => Mongo.string_to_uuid(observation._id)},
           projection: %{"_id" => true}
         ) do
        {:halt, {:error, "Observation with id '#{observation._id}' already exists", 409}}
      else
        {:cont, acc}
      end
    end)
  end

  defp validate_immunizations(patient_id_hash, immunizations) do
    Enum.reduce_while(immunizations, {:ok, immunizations}, fn immunization, acc ->
      case Immunizations.get(patient_id_hash, immunization.id) do
        {:ok, _} ->
          {:halt, {:error, "Immunization with id '#{immunization.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp validate_allergy_intolerances(patient_id_hash, allergy_intolerances) do
    Enum.reduce_while(allergy_intolerances, {:ok, allergy_intolerances}, fn allergy_intolerance, acc ->
      case AllergyIntolerances.get(patient_id_hash, allergy_intolerance.id) do
        {:ok, _} ->
          {:halt, {:error, "Allergy intolerance with id '#{allergy_intolerance.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp decode_signed_data(signed_data) do
    with {:ok, %{"data" => data}} <- @digital_signature.decode(signed_data, []) do
      {:ok, data}
    else
      {:error, %{"error" => _} = error} -> {:ok, error, 422}
      error -> {:ok, error, 500}
    end
  end

  defp validate_signed_data(signed_data) do
    with {:ok, %{"content" => _, "signer" => _}} = validation_result <- Signature.validate(signed_data) do
      validation_result
    else
      {:error, error} -> {:error, error, 422}
    end
  end

  defp validate_signatures(signer, employee_id, user_id, client_id) do
    case EncounterValidations.validate_signatures(signer, employee_id, user_id, client_id) do
      :ok -> :ok
      {:error, error} -> {:ok, error, 409}
    end
  end
end
